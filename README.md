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
