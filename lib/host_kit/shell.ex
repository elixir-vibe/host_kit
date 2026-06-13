defmodule HostKit.Shell do
  @moduledoc """
  POSIX shell rendering for the few HostKit paths that must cross `sh -c` or SSH exec.

  Prefer structured argv execution (`System.cmd/3`, `HostKit.Resources.Command.exec`) whenever possible.
  Elixir's `System.cmd/3` passes arguments as argv and explicitly does not require shell
  quoting. This module exists only for boundaries that are inherently shell strings, such as
  remote SSH command lines and package-manager probes that use shell operators.
  """

  @spec escape(term()) :: String.t()
  def escape(value) do
    "'" <> String.replace(to_string(value), "'", "'\\''") <> "'"
  end

  @spec join([term()]) :: String.t()
  def join(parts), do: Enum.map_join(parts, " ", &escape/1)

  @spec env(map() | keyword()) :: String.t()
  def env(values) when is_map(values), do: values |> Map.to_list() |> env()

  def env(values) when is_list(values) do
    Enum.map_join(values, " ", fn {key, value} -> "#{key}=#{escape(value)}" end)
  end
end
