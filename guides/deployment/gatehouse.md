# Gatehouse edge proxy

Gatehouse is the BEAM-native edge proxy/runtime for HostKit-managed hosts. HostKit writes the `Gatehouse.Config` file, installs a systemd service for an already-built Gatehouse release, and waits for the service to become active.

```elixir
use HostKit.DSL, providers: [HostKit.Providers.Gatehouse]

project :edge do
  account :gatehouse, system: true, home: "/var/lib/gatehouse"

  service :hello_phoenix do
    endpoint :http, port: 4000, protocol: :http, health: "/health"
  end

  gatehouse_release :edge,
    source: [github: "dannote/gatehouse", ref: "main"],
    release_path: "/opt/gatehouse"

  proxy :edge, provider: :gatehouse, path: "/etc/gatehouse/config.exs" do
    service :app do
      host "app.example.com"
      target :main, to: endpoint(:hello_phoenix, :http), active: true
    end
  end

  gatehouse :edge,
    release_path: "/opt/gatehouse",
    config_path: "/etc/gatehouse/config.exs",
    state_path: "/var/lib/gatehouse/state.etf",
    run_as: account(:gatehouse)
end
```

The `gatehouse_release` recipe builds and installs the Gatehouse release. The `proxy` block remains the source of Gatehouse routing config. The `gatehouse` recipe manages runtime scaffolding around that config:

- config/state/env directories
- `/etc/gatehouse/env`
- `gatehouse.service`
- readiness check for systemd active state

Declare the runtime account explicitly with `account`; the runtime recipe consumes it with `run_as: account(:gatehouse)`.
