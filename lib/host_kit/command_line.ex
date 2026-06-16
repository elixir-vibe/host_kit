defmodule HostKit.CommandLine do
  @moduledoc "A parsed or built simple command line stored as argv."

  defstruct source: nil, command: nil, args: [], ast: nil

  @type option_style :: :gnu | :equals | :single_dash | :short | :underscore
  @type t :: %__MODULE__{
          source: String.t() | nil,
          command: String.t(),
          args: [String.t()],
          ast: term()
        }

  @doc "Builds a command line from a command, positional args, and structured CLI options."
  @spec argv(String.t(), keyword()) :: t()
  def argv(command, opts \\ []) when is_binary(command) do
    args = Keyword.get(opts, :args, [])
    trailing = Keyword.get(opts, :trailing, [])
    option_style = Keyword.get(opts, :style, Keyword.get(opts, :opts_style, :gnu))
    option_args = opts |> Keyword.get(:opts, []) |> option_args(option_style)

    %__MODULE__{command: command, args: Enum.map(args ++ option_args ++ trailing, &to_string/1)}
  end

  @doc "Builds a Mix task command line."
  @spec mix(String.t() | atom(), keyword()) :: t()
  def mix(task, opts \\ []) when is_binary(task) or is_atom(task) do
    {command, opts} = Keyword.pop(opts, :command, "mix")
    argv(command, prepend_arg(opts, task))
  end

  @doc "Builds an Elixir command line."
  @spec elixir(keyword() | String.t() | [String.t()], keyword()) :: t()
  def elixir(opts \\ [])

  def elixir(opts) when is_list(opts) do
    {command, opts} = Keyword.pop(opts, :command, "elixir")
    argv(command, opts)
  end

  def elixir(script) when is_binary(script), do: elixir(script, [])

  def elixir(script_or_args, opts) when is_binary(script_or_args) or is_list(script_or_args) do
    {command, opts} = Keyword.pop(opts, :command, "elixir")
    argv(command, prepend_args(opts, List.wrap(script_or_args)))
  end

  @doc "Normalizes a HostKit command shape into `{command, args}` argv form."
  @spec to_exec(t() | String.t() | {term(), [term()]} | [term()]) :: {String.t(), [String.t()]}
  def to_exec(%__MODULE__{command: command, args: args}), do: {command, args}

  def to_exec(command) when is_binary(command),
    do: command |> parse!() |> to_exec()

  def to_exec({command, args}), do: {to_string(command), Enum.map(args, &to_string/1)}
  def to_exec([command | args]), do: to_exec({command, args})

  @spec parse(String.t()) :: {:ok, t()} | {:error, term()}
  def parse(source) when is_binary(source) do
    with {:ok, script} <- parse_bash(source),
         {:ok, command} <- single_simple_command(script),
         :ok <- no_shell_features(command),
         {:ok, command_name} <- literal_word(command.name),
         {:ok, args} <- literal_words(command.args) do
      {:ok, %__MODULE__{source: source, command: command_name, args: args, ast: nil}}
    end
  end

  @spec parse!(String.t()) :: t()
  def parse!(source) do
    case parse(source) do
      {:ok, command_line} ->
        command_line

      {:error, reason} ->
        raise ArgumentError, "invalid HostKit ~SH command: #{format_error(reason)}"
    end
  end

  defp prepend_arg(opts, arg), do: prepend_args(opts, [arg])

  defp prepend_args(opts, args) do
    args = Enum.map(args, &to_string/1)
    Keyword.update(opts, :args, args, fn existing -> args ++ List.wrap(existing) end)
  end

  defp option_args(opts, style) do
    Enum.flat_map(opts, fn {name, value} -> option_arg(name, value, style) end)
  end

  defp option_arg(_name, value, _style) when value in [false, nil], do: []
  defp option_arg(name, true, style), do: [flag_name(name, style)]

  defp option_arg(name, values, style) when is_list(values) do
    Enum.flat_map(values, &option_arg(name, &1, style))
  end

  defp option_arg(name, value, :equals), do: ["#{flag_name(name, :gnu)}=#{value}"]
  defp option_arg(name, value, style), do: [flag_name(name, style), to_string(value)]

  defp flag_name(name, :gnu), do: "--" <> dashed_name(name)
  defp flag_name(name, :equals), do: flag_name(name, :gnu)
  defp flag_name(name, :single_dash), do: "-" <> dashed_name(name)
  defp flag_name(name, :short), do: "-" <> to_string(name)
  defp flag_name(name, :underscore), do: "--" <> to_string(name)

  defp dashed_name(name), do: name |> to_string() |> String.replace("_", "-")

  defp parse_bash(source) do
    case Bash.Parser.parse(source) do
      {:ok, script} -> {:ok, script}
      {:error, reason, line, column} -> {:error, {:syntax, reason, line, column}}
    end
  end

  defp single_simple_command(%Bash.Script{statements: [%Bash.AST.Command{} = command]}),
    do: {:ok, command}

  defp single_simple_command(%Bash.Script{}),
    do: {:error, :not_single_simple_command}

  defp no_shell_features(%Bash.AST.Command{redirects: [], env_assignments: []}), do: :ok

  defp no_shell_features(%Bash.AST.Command{redirects: [_ | _]}),
    do: {:error, :redirects_not_allowed}

  defp no_shell_features(%Bash.AST.Command{env_assignments: [_ | _]}),
    do: {:error, :env_assignments_not_allowed}

  defp literal_words(words) do
    Enum.reduce_while(words, {:ok, []}, fn word, {:ok, acc} ->
      case literal_word(word) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp literal_word(%Bash.AST.Word{parts: parts}) do
    if Enum.all?(parts, &match?({:literal, _part}, &1)) do
      {:ok, Enum.map_join(parts, fn {:literal, part} -> part end)}
    else
      {:error, :expansions_not_allowed}
    end
  end

  defp format_error({:syntax, reason, line, column}), do: "#{reason} at #{line}:#{column}"
  defp format_error(:not_single_simple_command), do: "expected exactly one simple command"
  defp format_error(:redirects_not_allowed), do: "redirections require ~BASH"

  defp format_error(:env_assignments_not_allowed),
    do: "inline env assignments require explicit env:"

  defp format_error(:expansions_not_allowed), do: "expansions require ~BASH"
  defp format_error(reason), do: inspect(reason)
end
