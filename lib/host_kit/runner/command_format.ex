defmodule HostKit.Runner.CommandFormat do
  @moduledoc "Concise formatting for runner commands."

  @spec format(String.t(), [term()], keyword()) :: String.t()
  def format(command, args, opts \\ []) do
    max = Keyword.get(opts, :max, 220)
    format_command(command, args) |> truncate(max)
  end

  @spec script_summary(String.t()) :: String.t()
  def script_summary(script) do
    hash = :crypto.hash(:sha256, script) |> Base.encode16(case: :lower) |> binary_part(0, 12)
    lines = script |> String.split("\n") |> length()
    first_line = script |> String.split("\n", parts: 2) |> hd() |> String.trim() |> truncate(80)
    "<script sha256=#{hash} lines=#{lines} first=#{inspect(first_line)}>"
  end

  defp format_command("sh", ["-c", script]) when is_binary(script) do
    "sh -c #{script_summary(script)}"
  end

  defp format_command("sudo", ["sh", "-c", script]) when is_binary(script) do
    "sudo sh -c #{script_summary(script)}"
  end

  defp format_command(command, args) do
    [command | args]
    |> Enum.map_join(" ", &format_arg/1)
  end

  defp format_arg(arg) when is_binary(arg),
    do: if(String.contains?(arg, " "), do: inspect(arg), else: arg)

  defp format_arg(arg), do: inspect(arg)

  defp truncate(value, max) when byte_size(value) > max, do: binary_part(value, 0, max) <> "…"
  defp truncate(value, _max), do: value
end
