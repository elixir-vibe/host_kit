# HostKit

Elixir-native host infrastructure declarations, planning, and runtime control.

HostKit is intended to be used from a normal Mix project with `.exs` infrastructure files. The DSL compiles to plain inspectable structs; Mix tasks are wrappers around the runtime API.

## Design

- Core owns systemd/systemdkit persistent units.
- Core owns unitctl transient runtime primitives.
- Integrations such as Caddy, Forgejo, object storage, and monitoring are providers.
- DSL evaluation never applies changes to a host.
- Planning and rendering are available as runtime APIs.

## Example

```elixir
use HostKit.DSL

project :toys do
  roots source: "/opt/toys/src",
        data: "/srv/toys",
        state: "/var/lib/toys",
        config: "/etc/toys"

  prefixes user: "toys-", unit: "toys-"

  host :elixir_toys do
    hostname "elixir.toys"
    user "dannote"
    sudo true
  end

  service :exograph do
    system_user "toys-exograph", home: "/var/lib/toys/exograph/home"
    directory "/srv/toys/exograph", owner: "toys-exograph", group: "toys-exograph", mode: 0o755

    daemon "toys-exograph.service" do
      description "Exograph search"
      after_target :network_online
      wants :network_online
      service_user "toys-exograph"
      working_directory "/opt/toys/src/exograph"
      exec_start ["/usr/local/bin/mix", "exograph.index.hex", "--web", "--port", "4200"]
      restart :on_failure
      restart_sec 10
      hardening :web_service
      read_write_paths ["/srv/toys/exograph", "/var/lib/toys/exograph"]
      wanted_by :multi_user
    end
  end
end
```

## Providers

Providers can contribute DSL modules, resource types, renderers, validators, and read/plan/apply lifecycle operations. Systemd and Unitctl are core primitives, not providers; integrations such as Caddy should be providers.

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

## Host bootstrap packages and mise-managed runtimes

HostKit can install OS packages through the target package manager. The DSL is distribution-neutral by default and can be pinned to a manager when needed.

```elixir
service :bootstrap do
  package :ca_certificates
  package :build_essential, as: "build-essential", update: true
end
```

HostKit can also bootstrap `mise` and install system-wide tool versions. This is intended for host bootstrap and workspace agents; application services should still prefer packaged release artifacts where possible.

```elixir
service :bootstrap do
  mise path: "/usr/local/bin/mise", system_data_dir: "/usr/local/share/mise" do
    tool :erlang, "29.0.2"
    tool :elixir, "1.20.1"
  end
end
```

This applies through the `mise` CLI contract: it installs the binary with `mise.run` when missing, then runs `mise install --system` with `MISE_SYSTEM_DATA_DIR` set.

Package planning resolves semantic package names through Repology and caches responses in `.host_kit/cache/repology` for 24 hours by default. Use locks for deterministic apply:

```sh
mix host_kit.plan --write-package-lock host_kit.package.lock infra/config.exs
mix host_kit.apply --package-lock host_kit.package.lock --confirm infra/config.exs
```

Plan/apply artifacts make remote changes inspectable before apply. Prefer declaring the remote host in normal `.exs` HostKit config and selecting it with `--host`:

```elixir
use HostKit.DSL

project :infra do
  host :prod do
    hostname "host.example"
    user "root"
    sudo true

    ssh identity_file: Path.expand("~/.ssh/id_ed25519"),
        password: secret_env("HOSTKIT_SSH_PASSWORD"),
        silently_accept_hosts: true
  end
end
```

```sh
mix host_kit.plan --host prod \
  --package-lock host_kit.package.lock \
  --out host_kit.plan.json infra/config.exs

mix host_kit.apply --host prod \
  --plan host_kit.plan.json --confirm infra/config.exs
```

Plan artifacts are JSON and intended to be inspectable. Secret references are stored as references, not values, for example:

```json
{
  "$type": "struct",
  "module": "Elixir.HostKit.Secret",
  "fields": {
    "source": {
      "$type": "tuple",
      "items": [
        {"$type": "atom", "value": "env"},
        "HOSTKIT_SSH_PASSWORD"
      ]
    }
  }
}
```

`secret_env/1` records an environment-backed secret reference and resolves it only at the control-plane boundary that needs the value. Use it for HostKit's own credentials, such as SSH passwords or future provider API tokens. Target application environment files use the env-file DSL, which is backed by the same secret reference type:

```elixir
env_file "/etc/app/app.env" do
  set :mix_env, :prod
  secret :database_url, env: "DATABASE_URL"
end
```

Raw SSH flags remain available as an escape hatch: `--remote`, `--user`, `--port`, `--identity-file`, `--password`, and `--password-env`.

For Linux integration testing, use Incus as the lightweight native container/VM backend:

```sh
HOSTKIT_INCUS_SUDO=true HOSTKIT_SSH_PUBLIC_KEY=$HOME/.ssh/id_ed25519.pub \
  scripts/incus_integration_vm.sh ensure
HOSTKIT_INCUS_SUDO=true scripts/incus_integration_vm.sh ip
```

Set `HOSTKIT_INCUS_TYPE=vm` to launch an Incus VM instead of the default container, and `HOSTKIT_INCUS_INSTANCE=name` to change the instance name. Run the remote CLI integration against Incus with `HOSTKIT_INTEGRATION_TOOL=incus`, or against a pre-existing host declared in `.exs` config with `HOSTKIT_INTEGRATION_TOOL=remote HOSTKIT_INTEGRATION_CONFIG=examples/integration_hosts.example.exs`.

A real remote validation can use the same host config and a shell-provided secret:

```sh
HOSTKIT_SSH_PASSWORD='...' \
HOSTKIT_INTEGRATION_TOOL=remote \
HOSTKIT_INTEGRATION_CONFIG=examples/integration_hosts.example.exs \
mix test test/integration/cli_remote_test.exs --include integration
```

## Project-local DSLs

Use `HostKit.ProjectDSL` in consuming projects to build local conventions without baking them into HostKit.
Load project-local DSL files explicitly through the runtime API or Mix task `--require` option:

```elixir
# infra/toys_infra.exs
defmodule ToysInfra do
  use HostKit.ProjectDSL

  root :source, "/opt/toys/src"
  root :data, "/srv/toys"
  root :state, "/var/lib/toys"
  root :config, "/etc/toys"

  prefix :user, "toys-"
  prefix :unit, "toys-"

  defservice :toy_service do
    let :service_user, do: prefixed(:user, service_name())
    let :unit_name, do: prefixed(:unit, service_name()) <> ".service"

    path :source_dir, root(:source), service_name()
    path :data_dir, root(:data), service_name()
    path :state_dir, root(:state), service_name()
    path :config_dir, root(:config), service_name()

    macro :standard_user do
      system_user service_user(), home: state_path("home")
    end
  end
end
```

```elixir
# infra/config.exs
use HostKit.DSL, providers: [HostKit.Providers.Caddy]
use ToysInfra

project :toys do
  toy_service :exograph do
    standard_user()

    systemd_service unit_name() do
      working_directory source_dir()
      read_write_paths [data_dir(), state_dir(), source_dir()]
    end
  end
end
```

## Runtime API

```elixir
{:ok, project} = HostKit.load("infra/config.exs", require: ["toys_infra.exs"])
{:ok, plan} = HostKit.plan(project)
#=> %HostKit.Plan{changes: [%HostKit.Change{action: :create, ...}]}

prod = HostKit.Target.ssh(:prod, host: "elixir.toys", user: "dannote", sudo: true)
{:ok, remote_plan} = HostKit.plan(project, target: prod, reader: HostKit.Remote)

HostKit.format_plan(plan)
{:ok, results} = HostKit.apply(plan, dry_run: true)

# Supported apply resources: users, directories, files, systemd services, and systemd timers.
{:ok, results} = HostKit.apply(plan, confirm: true, sudo: true)

# Command and filesystem operations are routed through a runner boundary.
{:ok, results} = HostKit.apply(plan, confirm: true, runner: HostKit.Runner.Local)

prod = HostKit.Target.ssh(:prod, host: "elixir.toys", user: "dannote", sudo: true)

{:ok, results} = HostKit.apply(plan, target: prod, confirm: true)

{:ok, conn} = HostKit.Runner.SSH.Connection.open(host: "elixir.toys", user: "dannote")
try do
  prod = HostKit.Target.ssh(:prod, runner: {HostKit.Runner.SSH.Connection, conn: conn}, sudo: true)
  {:ok, remote_plan} = HostKit.plan(project, target: prod, reader: HostKit.Remote)
after
  HostKit.Runner.SSH.Connection.close(conn)
end

{:ok, unit} = HostKit.Render.render(project, {:systemd_service, "toys-exograph.service"})
```

## Storage volumes

HostKit models storage as named metadata instead of repeated path strings:

```elixir
volume =
  HostKit.Storage.volume(:repositories,
    path: "/srv/toys/forgejo/repositories",
    owner: "toys-forgejo",
    group: "toys-forgejo",
    mode: 0o750,
    backup: true
  )

directory HostKit.Storage.directory(volume)
read_write_paths HostKit.Storage.read_write_paths([volume])
```

Service conventions can derive these paths without project-specific macros and later reuse the same volume metadata for systemd sandboxing, Unitctl transient runtimes, and backups.

```elixir
project :toys do
  roots data: "/srv/toys", config: "/etc/toys"
  prefixes user: "toys-", unit: "toys-"

  service :forgejo do
    storage :repositories, under: :data, path: "repositories", mode: 0o750, backup: true
    storage :config, under: :config, owner: "root", group: service_user(), writable: false, secret: true

    daemon unit_name() do
      run user: service_user(), read_write_paths: writable_storage_paths()
    end
  end
end
```

## HostKit agent

HostKit can run as a supervised OTP application. The supervision tree currently starts agent state and a monitor worker:

```elixir
HostKit.Agent.status()
HostKit.Agent.configure(project: project, target: HostKit.Target.local(:prod))
HostKit.Agent.run_plan()
HostKit.Agent.run_monitor()
```

HostKit can also declare its own outer systemd supervisor unit:

```elixir
HostKit.Agent.Systemd.service(
  exec_start: ["/opt/host_kit/bin/host_kit", "agent", "--config", "/etc/host_kit/config.exs"]
)
```

State snapshots can be written for audit/drift history:

```elixir
HostKit.State.write(plan, "/var/lib/host_kit/state/latest-plan.json")
HostKit.State.read("/var/lib/host_kit/state/latest-plan.json")
```

This gives a clean two-layer supervision model: OTP inside the BEAM and systemd outside it.

## Firewall policy

HostKit can declare project- or host-scoped firewall policy:

```elixir
firewall do
  allow tcp: 22, from: :any
  allow tcp: [80, 443], from: :any
  allow tcp: 9100, from: {10, 44, 0, 0, 24}
  deny :all
end
```

Host-scoped policy lives inside `host`:

```elixir
host :prod, hostname: "elixir.toys" do
  firewall do
    allow tcp: 22, from: :any
    deny :all
  end
end
```

Extract, render, plan, and apply policies with:

```elixir
HostKit.Firewall.policies(project)
HostKit.Firewall.Nftables.render(policy)
HostKit.plan(project, reader: HostKit.Local)
HostKit.apply(plan, confirm: true, nft_reload: true)
```

Firewall policy is written to `/etc/nftables.d/hostkit.nft` by default and validated with `nft -c -f` before optional reload.

## Workspace inside monitoring

Workspace services can declare checks that are intended to run inside the sandbox later via a workspace agent:

```elixir
workspace :blog, owner: :alice do
  service :preview do
    inside do
      monitor :mix, task: "test", every: "5m"
      monitor :port, port: 4000
      monitor :git, clean: true
    end
  end
end
```

Extract them with:

```elixir
HostKit.Workspace.inside_monitors(project)
```

## Workspace execution and tenants

Tenants can own workspaces:

```elixir
tenant :alice, quota: [memory: "4G"] do
  agent port: 4173
end
```

Workspace command specs can be built for transient execution:

```elixir
HostKit.Workspace.exec_spec(project, :alice, :blog, ["mix", "test"])
HostKit.Workspace.exec(project, :alice, :blog, ["mix", "test"])
```

Inside monitors currently return `:pending_workspace_agent`, reserving execution for the sandbox agent boundary.

## OpenTelemetry Collector config

Telemetry declarations can be converted to an OpenTelemetry Collector config map:

```elixir
HostKit.OtelCollector.config(project, endpoint: "otel.example:4317")
```

## Workspace sandbox profiles

Systemd-backed sandbox profiles can be applied inside daemons:

```elixir
workspace :blog, owner: :alice do
  service :preview do
    daemon unit_name() do
      run exec_start: ["mix", "phx.server"]
      sandbox :vibe_dev
    end
  end
end
```

Profiles include `:vibe_dev`, `:strict_app`, and `:untrusted`, and can be overridden:

```elixir
sandbox :untrusted,
  resources: [memory_max: "256M"],
  sandbox: [private_network: false]
```

## Workspace preview helper

Workspace services can expose a preview route with a named listener and Caddy site:

```elixir
workspace :blog, owner: :alice do
  service :preview do
    daemon unit_name() do
      run exec_start: ["mix", "phx.server"]
    end

    preview :http, port: 4000, domain: "alice-blog.dev.example.com"
  end
end
```

This expands to `listen :http`, a Caddy reverse proxy to that listener, an HTTP monitor, telemetry metadata, and Caddy access-log metadata.

## Workspace agent helper

Workspaces can declare the default sandbox agent service as ordinary HostKit resources:

```elixir
workspace :blog, owner: :alice do
  agent port: 4173
end
```

This expands to a service with a system user, workspace directory, systemd daemon, loopback listener, logs, telemetry, systemd monitor, and loopback-only network policy.

## Workspace scope

`workspace` scopes ordinary HostKit DSL for user sandboxes while keeping resources inspectable:

```elixir
workspace :blog, owner: :alice do
  service :preview do
    directory root_path(:data), mode: :private_dir

    daemon unit_name() do
      run exec_start: ["mix", "phx.server"]
      listen :http, port: 4000, on: :loopback
    end
  end
end
```

Inside a workspace, services get workspace metadata plus separate path and identity names:

```elixir
root_path(:data) # .../alice/blog/preview
unit_name()      # prefix-alice-blog-preview.service
```

## Named listeners

Services can declare named listeners and reuse them from provider declarations:

```elixir
daemon unit_name() do
  run exec_start: ["/usr/bin/env", "true"]
  listen :http, port: 3000, on: :loopback
end

caddy_site :web, "web.example.com" do
  reverse_proxy listener(:http)
end
```

Named listeners are stored as service metadata and render Caddy upstreams like `127.0.0.1:3000` at the provider boundary.

## Network addresses and policy

Network addresses can use Elixir tuple forms and semantic aliases:

```elixir
listen 3000, on: :loopback
listen 4000, on: {127, 0, 0, 1}
network_policy deny: :all, allow: [:loopback, {10, 44, 0, 0, 24}]
```

Systemd services compile network policy to:

```ini
IPAddressDeny=any
IPAddressAllow=localhost 10.44.0.0/24
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
```

## Log management intent

Log management can be declared globally, per service, or on individual resources:

```elixir
observability do
  logs driver: :journald,
       retention: "14d",
       ship: true,
       attributes: [deployment_environment: :prod]
end
```

Systemd service log declarations also add unit directives:

```elixir
daemon unit_name() do
  run exec_start: ["/usr/bin/env", "true"]
  logs identifier: service_name(), stdout: :journal, stderr: :journal
end
```

Extract log intent with:

```elixir
HostKit.Logs.configs(project)
```

Read recent journald logs through local or remote targets:

```elixir
HostKit.Logs.read("toys-forgejo.service", target: prod, since: "1h")
HostKit.Logs.tail("toys-forgejo.service", target: prod, lines: 100)
```

## OpenTelemetry collection intent

Observability defaults can be enabled once at project or service scope and inherited by resources:

```elixir
observability do
  telemetry logs: true,
            metrics: true,
            traces: false,
            attributes: [deployment_environment: :prod]
end
```

Resource-level overrides are still available:

```elixir
daemon unit_name() do
  run exec_start: ["/usr/bin/env", "true"]
  telemetry logs: :journald, metrics: false, service_name: service_name()
end
```

Extract collection intent with:

```elixir
HostKit.Telemetry.signals(project)
```

Systemd services and Caddy sites get default collection intent even without global defaults:

```elixir
# systemd: logs: :journald, metrics: :systemd
# caddy: logs: :access, metrics: :http
```

## Monitoring metadata

Declarations can carry monitoring intent for a later monitoring service or config generator:

```elixir
daemon unit_name() do
  run exec_start: ["/usr/bin/env", "true"]
  monitor :systemd, expect: [state: :active], severity: :critical
end

caddy_site :web, "web.example.com" do
  reverse_proxy "127.0.0.1:4000"
  monitor :http, url: "https://web.example.com", expect: [status: 200]
end
```

Extract or run checks with:

```elixir
HostKit.Monitor.checks(project)
HostKit.Monitor.run(project, target: prod)
```

Initial execution supports systemd state, HTTP status, and filesystem existence checks.

## File modes

Mode values can be raw octal, semantic aliases, tuples, keywords, or capability lists:

```elixir
mode: :secret_group_file
mode: {:rw, :r, nil}
mode: [owner: :rw, group: :r]
mode: [:setgid, :owner_rwx, :group_rwx, :other_rx]
```

Resources store normalized integer modes, so plan/apply remains simple.

## Env files and secrets

HostKit has a Dotenvy-validated env file resource. Secret values are resolved at apply time and env-file drift compares metadata only by default.

```elixir
env_file root_path(:config, "env"), owner: "root", group: service_user(), mode: 0o640 do
  set :MIX_ENV, :prod
  set :PORT, 4000
  secret :SECRET_KEY_BASE, env: "SECRET_KEY_BASE"
end
```

## Runtime isolation

HostKit uses shared runtime isolation structs for persistent systemd units and future transient Unitctl workloads:

```elixir
sandbox = HostKit.Runtime.Sandbox.new(:strict_web)
resources = HostKit.Runtime.Resources.new(memory_max: "512M", cpu_quota: "50%")

service sandbox |> HostKit.Runtime.Sandbox.to_systemd_service_options()
service resources |> HostKit.Runtime.Resources.to_systemd_service_options()
```

Built-in profiles include `:web_service`, `:strict_web`, `:small`, `:medium`, and `:large`.

## Runtime controls

HostKit exposes Unitctl as its core transient runtime layer:

```elixir
{:ok, spec} =
  HostKit.Runtime.Spec.new(
    name: "demo-check",
    command: ["/usr/bin/env", "true"],
    sandbox: %{no_new_privileges: true, private_tmp: true}
  )

{:ok, instance} = HostKit.Runtime.start(spec)
{:ok, state} = HostKit.Runtime.status(instance)
:ok = HostKit.Runtime.stop(instance)
```

## Mix tasks

```sh
mix host_kit.dump --require toys_infra.exs infra/config.exs
mix host_kit.plan --require toys_infra.exs infra/config.exs
mix host_kit.plan --require toys_infra.exs infra/config.exs --local
mix host_kit.plan --require toys_infra.exs infra/config.exs --local --ignore systemd_service:toys-exograph.service
mix host_kit.plan --require toys_infra.exs infra/config.exs --remote elixir.toys --user dannote --sudo
mix host_kit.apply --require toys_infra.exs infra/config.exs --local --dry-run
mix host_kit.render --require toys_infra.exs infra/config.exs systemd_service toys-exograph.service
```
