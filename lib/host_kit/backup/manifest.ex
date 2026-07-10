defmodule HostKit.Backup.Manifest do
  @moduledoc "JSON manifest written for each HostKit backup run."

  @spec write!(Path.t(), map()) :: Path.t()
  def write!(destination, data) do
    path = Path.join(destination, "backup-#{Map.fetch!(data, :stamp)}.manifest.json")
    json = Jason.encode!(stringify_keys(data), pretty: true)
    :ok = HostKit.Runner.Local.write_file(path, json <> "\n", mode: 0o600)
    path
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(values) when is_list(values), do: Enum.map(values, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
