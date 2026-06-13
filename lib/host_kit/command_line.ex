defmodule HostKit.CommandLine do
  @moduledoc "A parsed, shell-like simple command line stored as argv."

  defstruct source: nil, command: nil, args: [], ast: nil

  @type t :: %__MODULE__{source: String.t(), command: String.t(), args: [String.t()], ast: term()}

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
