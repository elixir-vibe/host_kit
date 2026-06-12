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
  host :elixir_toys do
    hostname "elixir.toys"
    user "dannote"
    sudo true
  end

  service :exograph do
    system_user "toys-exograph", home: "/var/lib/toys/exograph/home"
    directory "/srv/toys/exograph", owner: "toys-exograph", group: "toys-exograph", mode: 0o755

    systemd_service "toys-exograph.service" do
      description "Exograph search"
      after_units ["network-online.target"]
      wants ["network-online.target"]
      service_user "toys-exograph"
      working_directory "/opt/toys/src/exograph"
      exec_start ["/usr/local/bin/mix", "exograph.index.hex", "--web", "--port", "4200"]
      restart :on_failure
      restart_sec 10
      hardening :web_service
      read_write_paths ["/srv/toys/exograph", "/var/lib/toys/exograph"]
      install wanted_by: "multi-user.target"
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

HostKit.format_plan(plan)
{:ok, results} = HostKit.apply(plan, dry_run: true)

# Supported apply resources: users, directories, files, systemd services, and systemd timers.
{:ok, results} = HostKit.apply(plan, confirm: true, sudo: true)

# Command and filesystem operations are routed through a runner boundary.
{:ok, results} = HostKit.apply(plan, confirm: true, runner: HostKit.Runner.Local)

prod = HostKit.Target.ssh(:prod, host: "elixir.toys", user: "dannote", sudo: true)

{:ok, results} = HostKit.apply(plan, target: prod, confirm: true)

{:ok, unit} = HostKit.Render.render(project, {:systemd_service, "toys-exograph.service"})
```

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
mix host_kit.apply --require toys_infra.exs infra/config.exs --local --dry-run
mix host_kit.render --require toys_infra.exs infra/config.exs systemd_service toys-exograph.service
```
