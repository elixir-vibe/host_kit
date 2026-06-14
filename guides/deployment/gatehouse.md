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

The full source-build deployment path is covered by an opt-in Incus integration test:

```sh
HOSTKIT_INTEGRATION=1 \
HOSTKIT_GATEHOUSE_DEPLOY_INTEGRATION=1 \
HOSTKIT_INTEGRATION_TOOL=incus \
HOSTKIT_INCUS_INTEGRATION=1 \
mix test test/integration/gatehouse_deploy_test.exs
```

That test builds Gatehouse from source on a Linux target, writes the generated config, starts `gatehouse.service`, and verifies systemd reports it active.
