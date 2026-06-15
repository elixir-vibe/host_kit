# HostKit

Elixir-native host management: declare a Linux host, bootstrap packages and runtimes, isolate services with systemd, wire provider integrations, review a plan artifact, then apply it locally or over SSH.

HostKit is for operating real machines without assuming the target already has Elixir, Mix, Docker, or your application runtime installed.

> [!NOTE]
> HostKit is currently published as a beta. The core planning/apply workflow is
> usable and documented, but DSL, provider, and recipe APIs may still change
> before a stable release.

## Why HostKit

Infrastructure code should be boring Elixir, not an opaque pile of shell scripts.

HostKit gives you:

- **Declarative host bootstrap** — OS packages, accounts, directories, files, templates, env files, structured INI/YAML configs, systemd units, firewall rules, and `mise` runtimes.
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
  roots data: "/srv/apps", config: "/etc/apps"

  host :app, at: "app.example.com" do
    ssh do
      user "root"
      identity_file Path.expand("~/.ssh/id_ed25519")
      accept_hosts true
      retry attempts: 3
    end
  end

  bootstrap do
    package :ca_certificates

    mise do
      tool :erlang, "29.0.2"
      tool :elixir, "1.20.1"
    end
  end

  service :api do
    account system: true
    storage :data, mode: 0o750
    storage :config, owner: "root", group: service_user(), mode: 0o750

    env :runtime do
      secret :database_url, env: "DATABASE_URL"
    end

    ini path(:config, "app.ini"), owner: "root", group: service_user(), mode: 0o640 do
      set "APP_NAME", "Example API"

      section "server" do
        set "HTTP_ADDR", "127.0.0.1"
        set "HTTP_PORT", 4000
        secret "JWT_SECRET", env: :redacted
      end
    end

    yaml path(:config, "health.yaml"),
      owner: "root",
      group: service_user(),
      mode: 0o640,
      content: [
        endpoints: [
          [name: "api", url: "http://127.0.0.1:4000/health", conditions: ["[STATUS] == 200"]]
        ]
      ]

    daemon do
      env :runtime
      exec ["/opt/api/bin/server"]

      isolate do
        memory_max "512M"
        writable :data
        network :loopback
      end

      listen :http, port: 4000
    end

    caddy_site "api.example.com" do
      reverse_proxy :http
    end
  end
end
```

This compiles to inspectable HostKit structs and renders ordinary Linux primitives: packages, files, templates, env files, structured config files, accounts, systemd units, Caddy site config, and systemd hardening directives such as `NoNewPrivileges=`, `ProtectSystem=`, `RestrictAddressFamilies=`, `ReadWritePaths=`, and memory limits. Secret/redacted structured config entries are omitted from public drift comparison by INI key or YAML path, so generated values can be modeled without leaking them into plans. See the [DSL design guidelines](guides/reference/dsl-guidelines.md) for naming, block shape, defaults, and reference style.

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

`secret_env/1` stores an environment-variable reference. Plan artifacts include the variable name, not the resolved secret value. Runtime callers can use `HostKit.Project.audit/2`, `HostKit.Project.read/2`, and `HostKit.Facts.collect/2` directly; `mix host_kit.audit`, `mix host_kit.read`, and `mix host_kit.facts` are wrappers around those inspectable APIs.

## Managed local demo instance

`host` is a connection endpoint. `instance` is a lifecycle-managed compute boundary. Backends such as Incus create/start/destroy the instance, while nested `host` and `service` declarations describe how HostKit connects into it and what should run inside.

```elixir
use HostKit.DSL

project :demo do
  instance :demo_vm do
    backend :incus, sudo: true
    image "images:ubuntu/24.04"
    kind :container
    lifecycle :ephemeral

    expose :ssh, host: 2222, guest: 22
    expose :web, host: 18_080, guest: 80

    host :guest, at: "127.0.0.1" do
      ssh do
        user "root"
        password "hostkit-demo"
        port 2222
        accept_hosts true
      end
    end

    service :web do
      package :caddy
    end
  end
end
```

Manage the declared instance through the backend-neutral instance CLI:

```sh
mix host_kit.instance ensure demo_vm infra/demo.exs
mix host_kit.instance status demo_vm infra/demo.exs
mix host_kit.instance destroy demo_vm infra/demo.exs
```

See [`examples/livebook_demo_instance.exs`](examples/livebook_demo_instance.exs) for the local Livebook demo target used by the notebook workflow.

## Interactive notebook

Deploy real services from Livebook with Kino inputs for SSH target/auth, plan review, explicit apply, and HTTP verification:

Static Caddy site:

[![Run Caddy notebook in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Felixir-vibe%2Fhost_kit%2Fblob%2Fmaster%2Fnotebooks%2Flearn%2Fdeploy_caddy_site.livemd)

Phoenix app from Git, with pinned source revision and source-aware build stamps:

[![Run Phoenix notebook in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Felixir-vibe%2Fhost_kit%2Fblob%2Fmaster%2Fnotebooks%2Flearn%2Fdeploy_phoenix_app.livemd)

The notebooks are self-contained and their deployment DSL cells are also exercised by the integration test suite.

## Documentation

- [Getting started](guides/introduction/getting-started.md)
- [Conventions and paths](guides/introduction/conventions-and-paths.md)
- [Remote bootstrap and plan artifacts](guides/deployment/remote-bootstrap.md)
- [Systemd isolation](guides/deployment/systemd-isolation.md)
- [Firewall and networking](guides/deployment/firewall-and-networking.md)
- [Workspaces and tenants](guides/workspaces/workspaces-and-tenants.md)
- [Observability and monitors](guides/operations/observability-and-monitors.md)
- [Timers and jobs](guides/operations/timers-and-jobs.md)
- [Deploy a Caddy site Livebook](notebooks/learn/deploy_caddy_site.livemd)
- [Deploy a Phoenix app Livebook](notebooks/learn/deploy_phoenix_app.livemd)
- [CLI reference](guides/reference/cli.md)
- [Full DSL/reference notes](guides/reference/full-reference.md)
- [Internal architecture](guides/reference/internal-architecture.md)
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
