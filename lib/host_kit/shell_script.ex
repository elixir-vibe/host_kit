defmodule HostKit.ShellScript do
  @moduledoc "A parsed Bash script with static command analysis metadata."

  defstruct source: nil, ast: nil, commands: []

  @type command_ref :: %{name: String.t(), line: pos_integer() | nil, column: pos_integer() | nil}
  @type t :: %__MODULE__{source: String.t(), ast: term(), commands: [command_ref()]}

  @spec parse(String.t()) :: {:ok, t()} | {:error, term()}
  def parse(source) when is_binary(source) do
    case Bash.Parser.parse(source) do
      {:ok, ast} -> {:ok, %__MODULE__{source: source, ast: nil, commands: commands(ast)}}
      {:error, reason, line, column} -> {:error, {:syntax, reason, line, column}}
    end
  end

  @spec parse!(String.t()) :: t()
  def parse!(source) do
    case parse(source) do
      {:ok, script} ->
        script

      {:error, {:syntax, reason, line, column}} ->
        raise ArgumentError, "invalid HostKit ~BASH script: #{reason} at #{line}:#{column}"
    end
  end

  defp commands(term),
    do: term |> collect_commands([]) |> Enum.reverse() |> Enum.uniq_by(& &1.name)

  defp collect_commands(%Bash.AST.Command{literal_name: name, meta: meta} = command, acc)
       when is_binary(name) do
    command
    |> Map.from_struct()
    |> Map.drop([:literal_name, :name])
    |> collect_commands([
      %{name: name, line: meta && meta.line, column: meta && meta.column} | acc
    ])
  end

  defp collect_commands(%_module{} = struct, acc),
    do: struct |> Map.from_struct() |> collect_commands(acc)

  defp collect_commands(map, acc) when is_map(map) do
    Enum.reduce(map, acc, fn {_key, value}, acc -> collect_commands(value, acc) end)
  end

  defp collect_commands(values, acc) when is_list(values) do
    Enum.reduce(values, acc, &collect_commands/2)
  end

  defp collect_commands(_term, acc), do: acc
end
