# Conventions and paths

HostKit projects can declare path roots and naming prefixes once, then derive service paths, account names, and unit names from those conventions.

This keeps host declarations DRY while still compiling to plain structs.

```elixir
use HostKit.DSL

project :toys do
  roots source: "/opt/toys/src",
        data: "/srv/toys",
        state: "/var/lib/toys",
        config: "/etc/toys"

  prefixes user: "toys-", unit: "toys-"

  service :forgejo, path: "git" do
    account system: true
    storage :data, mode: 0o750
    storage :state, mode: 0o750

    env :runtime do
      set :USER, service_user()
    end

    daemon do
      description "Forgejo"
      working_directory path(:source)
      env :runtime
      exec [Path.join(path(:source), "bin/forgejo"), "web"]

      isolate do
        writable :data
        writable :state
      end
    end
  end
end
```

Useful helpers:

- `roots source: ..., data: ..., state: ..., config: ...` declares project path roots.
- `prefixes user: ..., unit: ...` declares naming prefixes.
- `storage :data` defaults under the declared `:data` root.
- `env :runtime` defaults under the declared `:config` root.
- `path(:source)` resolves the current service's source path.
- `path(:run, "rpc.sock")` resolves the current service's runtime socket path.
- `path(:data, "repositories")` resolves an explicit child path when you need one.
- `service_name()` returns the current service name.
- `service_user()` returns the convention-derived service account name.
- `unit_name()` returns the convention-derived systemd unit name.
- `service :name, path: "slug"` overrides the path/identity slug for one service.

Common executable roots have defaults and can be overridden:

```elixir
# defaults
path(:bin, "mix")  # /usr/local/bin/mix
path(:sbin, "tool") # /usr/local/sbin/tool

# override
roots bin: "/opt/mise/shims"
```

For HostKit's own host-side tracking, the default roots are:

```elixir
roots hostkit_state: "/var/lib/hostkit"
# derived defaults:
# hostkit_runs: "/var/lib/hostkit/runs"
# hostkit_backups: "/var/lib/hostkit/backups"
```

Override `:hostkit_state` to move both derived roots, or override `:hostkit_runs` / `:hostkit_backups` individually.

For larger projects, wrap these conventions in a project-local DSL and load it with `--require`.
