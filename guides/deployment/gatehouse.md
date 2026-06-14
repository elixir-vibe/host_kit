# Gatehouse edge proxy

Gatehouse is the BEAM-native edge proxy/runtime for HostKit-managed hosts. HostKit writes the `Gatehouse.Config` file, installs a systemd service for an already-built Gatehouse release, and waits for the service to become active.

```elixir
use HostKit.DSL, providers: [HostKit.Providers.Gatehouse]

project :edge do
  service :hello_phoenix do
    endpoint :http, port: 4000, protocol: :http, health: "/health"
  end

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
    user: "gatehouse"
end
```

The `proxy` block remains the source of Gatehouse routing config. The `gatehouse` recipe manages runtime scaffolding around that config:

- system user
- config/state/env directories
- `/etc/gatehouse/env`
- `gatehouse.service`
- readiness check for systemd active state

For now the recipe assumes the Gatehouse release already exists at `release_path`. Building and deploying the Gatehouse release itself is intentionally separate so routing config can stabilize first.
