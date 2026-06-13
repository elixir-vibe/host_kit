# HostKit

Elixir-native host management: declare packages, runtimes, files, services, firewall policy, and provider integrations as plain inspectable structs; plan the change; review an artifact; then apply it locally or over SSH.

HostKit is for bootstrapping and operating real Linux hosts without assuming the machine already has Elixir, Mix, or your application runtime installed.

## Why HostKit

Infrastructure code should be boring Elixir, not an opaque pile of shell scripts.

HostKit gives you:

- **Declarative host bootstrap** — OS packages, users, directories, files, env files, systemd units, firewall rules, and `mise` runtimes.
- **Plan before apply** — read current state, produce a diff, write an inspectable JSON plan artifact, then apply exactly what was reviewed.
- **Distribution-aware packages** — semantic package names resolve through Repology and can be locked for deterministic applies.
- **No hidden Mix requirement on target hosts** — bootstrap can install prerequisites and BEAM tools through `mise`.
- **Host config in `.exs`** — normal Elixir syntax highlighting, macros, composition, and project-local DSLs.
- **Provider boundary** — integrations such as Caddy live as providers while core owns systemd/unitctl primitives.
- **Linux-native integration testing** — Incus containers/VMs replace macOS-only Lima flows on Linux.

## A small host

```elixir
use HostKit.DSL

project :prod do
  host :app do
    hostname "app.example.com"
    user "root"
    sudo true

    ssh identity_file: Path.expand("~/.ssh/id_ed25519"),
        silently_accept_hosts: true
  end

  service :bootstrap do
    package :ca_certificates
    package :build_essential, as: "build-essential", update: true

    mise path: "/usr/local/bin/mise", system_data_dir: "/usr/local/share/mise" do
      tool :erlang, "29.0.2"
      tool :elixir, "1.20.1"
    end
  end
end
```

Plan and apply:

```sh
mix host_kit.plan --host app --write-package-lock host_kit.package.lock --out host_kit.plan.json infra/config.exs
mix host_kit.apply --host app --plan host_kit.plan.json --confirm infra/config.exs
```

For password-only hosts, keep the secret out of config and shell history:

```elixir
ssh password: secret_env("HOSTKIT_SSH_PASSWORD"),
    silently_accept_hosts: true
```

`secret_env/1` stores a reference to the environment variable. Plan artifacts include the reference name, not the resolved value.

## Caddy provider example

```elixir
use HostKit.DSL, providers: [HostKit.Providers.Caddy]

project :demo, providers: [HostKit.Providers.Caddy] do
  provider :caddy, HostKit.Providers.Caddy do
    set :sites_dir, "/etc/caddy/sites"
  end

  service :web do
    caddy_site :web, "example.com", path: "web.caddy" do
      encode [:zstd, :gzip]
      reverse_proxy "127.0.0.1:4000"
    end
  end
end
```

## Documentation

- [Getting started](guides/introduction/getting-started.md)
- [Remote bootstrap and plan artifacts](guides/deployment/remote-bootstrap.md)
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
