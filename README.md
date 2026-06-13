# HostKit

Elixir-native host management: declare a Linux host, bootstrap packages and runtimes, isolate services with systemd, wire provider integrations, review a plan artifact, then apply it locally or over SSH.

HostKit is for operating real machines without assuming the target already has Elixir, Mix, Docker, or your application runtime installed.

## Why HostKit

Infrastructure code should be boring Elixir, not an opaque pile of shell scripts.

HostKit gives you:

- **Declarative host bootstrap** — OS packages, users, directories, files, env files, systemd units, firewall rules, and `mise` runtimes.
- **Docker-less service isolation** — systemd sandboxing, resource limits, network policy, read/write path allowlists, loopback listeners, and managed env files.
- **Plan before apply** — read current state, produce a diff, write an inspectable JSON artifact, then apply exactly what was reviewed.
- **Distribution-aware packages** — semantic package names resolve through Repology and can be locked for deterministic applies.
- **No hidden Mix requirement on target hosts** — bootstrap can install prerequisites and BEAM tools through `mise`.
- **Host config in `.exs`** — syntax highlighting, macros, composition, and project-local DSLs.
- **Provider boundary** — integrations such as Caddy live as providers while core owns systemd/unitctl primitives.
- **Linux-native integration testing** — Incus containers/VMs replace macOS-only Lima flows on Linux.

## One file: host, runtime, isolated service, reverse proxy

The complete example lives in [`examples/full_host.exs`](examples/full_host.exs) and is loaded by the test suite so it does not drift.

```elixir
use HostKit.DSL, providers: [HostKit.Providers.Caddy]

project :prod do
  host :app do
    hostname "app.example.com"
    user "root"
    sudo true
    ssh identity_file: Path.expand("~/.ssh/id_ed25519"), silently_accept_hosts: true
  end

  service :bootstrap do
    package :ca_certificates

    mise path: "/usr/local/bin/mise", system_data_dir: "/usr/local/share/mise" do
      tool :erlang, "29.0.2"
      tool :elixir, "1.20.1"
    end
  end

  service :api do
    system_user "api", home: "/var/lib/api"
    directory "/var/lib/api", owner: "api", group: "api", mode: 0o750

    env_file "/etc/api/api.env", owner: "root", group: "api" do
      secret :database_url, env: "DATABASE_URL"
    end

    daemon "api.service" do
      service_user "api"
      environment_file "/etc/api/api.env"
      exec_start ["/opt/api/bin/server"]

      sandbox :strict_app,
        resources: [memory_max: "512M"],
        sandbox: [read_write_paths: ["/var/lib/api"]]

      listen :http, port: 4000, on: :loopback
      wanted_by :multi_user
    end

    caddy_site :api, "api.example.com" do
      reverse_proxy listener(:http)
    end
  end
end
```

This compiles to inspectable HostKit structs and renders ordinary Linux primitives: packages, files, env files, system users, systemd units, Caddy site config, and systemd hardening directives such as `NoNewPrivileges=`, `ProtectSystem=`, `RestrictAddressFamilies=`, `ReadWritePaths=`, and memory limits.

Plan, review, apply:

```sh
mix host_kit.plan --host app \
  --write-package-lock host_kit.package.lock \
  --out host_kit.plan.json \
  infra/config.exs

mix host_kit.apply --host app \
  --plan host_kit.plan.json \
  --confirm \
  infra/config.exs
```

`secret_env/1` stores an environment-variable reference. Plan artifacts include the variable name, not the resolved secret value.

## Documentation

- [Getting started](guides/introduction/getting-started.md)
- [Conventions and paths](guides/introduction/conventions-and-paths.md)
- [Remote bootstrap and plan artifacts](guides/deployment/remote-bootstrap.md)
- [Systemd isolation](guides/deployment/systemd-isolation.md)
- [Firewall and networking](guides/deployment/firewall-and-networking.md)
- [Workspaces and tenants](guides/workspaces/workspaces-and-tenants.md)
- [Observability and monitors](guides/operations/observability-and-monitors.md)
- [Timers and jobs](guides/operations/timers-and-jobs.md)
- [CLI reference](guides/reference/cli.md)
- [Full DSL/reference notes](guides/reference/full-reference.md)
- [Changelog](CHANGELOG.md)

## Development

```sh
mix deps.get
mix ci
```

Run the Incus-backed remote integration on Linux:

```sh
HOSTKIT_INCUS_SUDO=true HOSTKIT_SSH_PUBLIC_KEY=$HOME/.ssh/id_ed25519.pub \
  scripts/incus_integration_vm.sh ensure

HOSTKIT_INTEGRATION_TOOL=incus HOSTKIT_INCUS_SUDO=true \
  mix test test/integration/cli_remote_test.exs --include integration
```

## Status

HostKit is early and intentionally evolving. Runtime APIs come first; Mix tasks wrap them. DSLs compile to plain structs so plans and artifacts remain inspectable.

## License

MIT
