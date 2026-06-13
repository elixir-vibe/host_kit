defmodule HostKit.OtelCollector do
  @moduledoc "Builds OpenTelemetry Collector config maps from HostKit telemetry declarations."

  def config(project, opts \\ []) do
    signals = HostKit.Telemetry.signals(project)

    %{
      receivers: receivers(signals),
      processors: %{batch: %{}},
      exporters: exporters(opts),
      service: %{pipelines: pipelines(signals, opts)}
    }
  end

  defp receivers(signals) do
    signals
    |> Enum.filter(&(&1.logs == :journald))
    |> Map.new(fn signal ->
      name = receiver_name(signal)
      {name, %{units: [unit_name(signal.resource_id)]}}
    end)
  end

  defp exporters(opts), do: %{otlp: %{endpoint: Keyword.get(opts, :endpoint, "localhost:4317")}}

  defp pipelines(signals, opts) do
    log_receivers = signals |> Enum.filter(&(&1.logs == :journald)) |> Enum.map(&receiver_name/1)

    if log_receivers == [] do
      %{}
    else
      %{
        logs: %{
          receivers: log_receivers,
          processors: [:batch],
          exporters: Keyword.get(opts, :exporters, [:otlp])
        }
      }
    end
  end

  defp receiver_name(signal), do: "journald/#{unit_name(signal.resource_id)}"
  defp unit_name({:systemd_service, unit}), do: unit
  defp unit_name({:systemd_timer, unit}), do: unit
  defp unit_name(other), do: to_string(other)
end
