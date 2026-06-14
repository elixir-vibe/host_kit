defmodule HostKit.Error do
  @moduledoc "Concise formatting for common HostKit runtime error terms."

  @spec format(term(), keyword()) :: String.t()
  def format(reason, opts \\ []) do
    max = Keyword.get(opts, :max, 1_000)

    reason
    |> format_reason()
    |> truncate(max)
  end

  defp format_reason({:command_failed, command, args, status, output}) do
    "command failed (#{status}): #{format_command(command, args)}#{format_output(output)}"
  end

  defp format_reason({resource_id, reason}) when is_tuple(resource_id) do
    "#{inspect(resource_id)}: #{format_reason(reason)}"
  end

  defp format_reason({:readiness_timeout, name, errors}) do
    "readiness #{name} timed out: #{format_readiness_errors(errors)}"
  end

  defp format_reason(reason), do: inspect(reason, limit: 10, printable_limit: 500)

  defp format_readiness_errors(errors) do
    errors
    |> List.wrap()
    |> Enum.map_join("; ", fn
      {_check, {:error, reason}} -> format_reason(reason)
      {check, reason} -> "#{inspect(check, limit: 5)}: #{format_reason(reason)}"
      reason -> format_reason(reason)
    end)
  end

  defp format_output(nil), do: ""
  defp format_output(""), do: ""
  defp format_output(output), do: "\n" <> truncate(String.trim(to_string(output)), 500)

  defp format_command(command, args), do: HostKit.Runner.Command.format(command, args)

  defp truncate(value, max) when byte_size(value) > max, do: binary_part(value, 0, max) <> "…"
  defp truncate(value, _max), do: value
end
