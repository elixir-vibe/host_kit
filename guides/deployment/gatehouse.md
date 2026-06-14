# Gatehouse edge proxy

Gatehouse is the BEAM-native edge proxy/runtime for HostKit-managed hosts. HostKit can now build the Gatehouse release, render semantic ingress into `Gatehouse.Config`, install the systemd service, and wait until it is active.

The deployment has three pieces:

1. `gatehouse_release` builds and installs the Gatehouse release.
2. `ingress` declares routing in provider-neutral HostKit terms.
3. `gatehouse` installs the runtime env/systemd scaffolding around the rendered config.

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

  service :edge do
    ingress :web,
      path: "/etc/gatehouse/config.exs",
      state: "/var/lib/gatehouse/state.etf" do
      server ":80" do
        route host: "app.example.com" do
          proxy to: endpoint(:hello_phoenix, :http)
        end
      end
    end
  end

  gatehouse :edge,
    release_path: "/opt/gatehouse",
    config_path: "/etc/gatehouse/config.exs",
    state_path: "/var/lib/gatehouse/state.etf",
    run_as: account(:gatehouse)
end
```

The same `ingress` declaration can also be consumed by the Caddy provider. HostKit resolves endpoint references at plan time, then renders Gatehouse targets as ordinary URLs.

`ingress` is the preferred public API for application routing. The lower-level `proxy ..., provider: :gatehouse` resource remains available as an advanced escape hatch when you need to express Gatehouse-specific listeners, services, balancing, health checks, drain behavior, or TLS details that are not yet modeled by provider-neutral ingress.

The deploy integration defaults to a target-side source build. This path is intentionally heavier, but validates the complete Linux deployment flow:

```sh
HOSTKIT_INTEGRATION=1 \
HOSTKIT_GATEHOUSE_DEPLOY_INTEGRATION=1 \
HOSTKIT_INTEGRATION_TOOL=incus \
HOSTKIT_INCUS_INTEGRATION=1 \
mix test test/integration/gatehouse_deploy_test.exs
```

There is also an experimental `HOSTKIT_GATEHOUSE_DEPLOY_MODE=prebuilt` path that builds a local release and uploads it to the target. Use it only when the local build host is ABI-compatible with the target OS; otherwise the release ERTS may require a newer glibc than the target provides.
