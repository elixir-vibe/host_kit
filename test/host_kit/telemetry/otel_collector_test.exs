defmodule HostKit.OtelCollectorTest do
  use ExUnit.Case, async: true

  test "builds collector config from journald telemetry signals" do
    service = %HostKit.Systemd.Service{
      name: "web.service",
      meta: %{telemetry: %{logs: :journald, metrics: false}}
    }

    project =
      HostKit.Project.new(:demo)
      |> HostKit.Project.add_service(HostKit.Service.new(:web, resources: [service]))

    config = HostKit.OtelCollector.config(project, endpoint: "otel.example:4317")

    assert config.receivers["journald/web.service"] == %{units: ["web.service"]}
    assert config.exporters.otlp.endpoint == "otel.example:4317"
    assert config.service.pipelines.logs.receivers == ["journald/web.service"]
  end
end
