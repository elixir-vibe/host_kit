# Observability and monitors

HostKit lets resources carry observability intent alongside their runtime declarations.

```elixir
use HostKit.DSL, providers: [HostKit.Providers.Caddy]

project :prod do
  observability do
    logs driver: :journald,
         retention: "14d",
         ship: true,
         attributes: [deployment_environment: :prod]

    telemetry service: "hostkit-prod",
              endpoint: "otel.example.com:4317"
  end

  service :api do
    daemon do
      description "API"
      exec ["/opt/api/bin/server"]
      listen :http, port: 4000
      logs stdout: :journal, stderr: :journal, identifier: "api"
      monitor :systemd, name: :api_unit, expect: [state: :active], severity: :critical
    end

    caddy_site "api.example.com" do
      reverse_proxy :http
      logs driver: :access, attributes: [service_name: :api]
      monitor :http, name: :api_http, url: "https://api.example.com", expect: [status: 200]
    end
  end
end
```

The declarations can be used to:

- render systemd logging directives,
- attach log metadata to resources,
- derive OpenTelemetry Collector config,
- collect expected checks with `HostKit.Monitor.checks/1`,
- keep monitoring intent next to the resource it verifies.

Monitors can also attach to the most recently declared resource:

```elixir
service :data do
  directory "/srv/data", mode: :private_dir
  monitor :filesystem, name: :data_dir, expect: [exists: true]
end
```

This keeps checks stable even as resources are refactored.
