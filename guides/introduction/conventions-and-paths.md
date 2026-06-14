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

  service :forgejo do
    # Optional: override the path/identity slug used by root_path/2 and service_user/0.
    path_name "git"

    account service_user(), system: true, home: root_path(:state, "home")

    directory root_path(:data), owner: service_user(), group: service_user(), mode: 0o750
    directory root_path(:config), owner: "root", group: service_user(), mode: 0o750

    daemon unit_name() do
      description "Forgejo"
      service_user service_user()
      working_directory root_path(:source)
      exec_start [Path.join(root_path(:source), "bin/forgejo"), "web"]
      read_write_paths [root_path(:data), root_path(:state)]
      wanted_by :multi_user
    end
  end
end
```

Useful helpers:

- `roots source: ..., data: ..., state: ..., config: ...` declares project path roots.
- `prefixes user: ..., unit: ...` declares naming prefixes.
- `root_path(:data)` resolves the current service's data path.
- `root_path(:data, "repositories")` resolves a child path.
- `service_name()` returns the current service name.
- `service_user()` returns the convention-derived service account name.
- `unit_name()` returns the convention-derived systemd unit name.
- `path_name "slug"` overrides the path/identity slug for one service.

For larger projects, wrap these conventions in a project-local DSL and load it with `--require`.
