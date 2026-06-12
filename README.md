# HostKit

Elixir-native host infrastructure declarations, planning, and runtime control.

HostKit is intended to be used from a normal Mix project with `.exs` infrastructure files. The DSL compiles to plain inspectable structs; Mix tasks are wrappers around the runtime API.

## Design

- Core owns systemd/systemdkit persistent units.
- Core owns unitctl transient runtime primitives.
- Integrations such as Caddy, Forgejo, object storage, and monitoring are plugins.
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

## Runtime API

```elixir
{:ok, project} = HostKit.load("infra/config.exs")
{:ok, plan} = HostKit.plan(project)
{:ok, unit} = HostKit.Render.render(project, {:systemd_service, "toys-exograph.service"})
```

## Mix tasks

```sh
mix host_kit.dump infra/config.exs
mix host_kit.plan infra/config.exs
mix host_kit.render infra/config.exs systemd_service toys-exograph.service
```
