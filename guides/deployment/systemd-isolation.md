# Systemd isolation

HostKit is designed to make Docker optional for many single-host services. You can run each service as its own Unix user, give it explicit writable paths, wire managed env files, restrict network/address families, and apply systemd sandboxing/resource limits.

```elixir
use HostKit.DSL

project :prod do
  roots source: "/opt/apps", data: "/srv/apps", state: "/var/lib/apps", config: "/etc/apps"
  prefixes user: "app-", unit: "app-"

  service :api do
    system_user service_user(), home: root_path(:state, "home")

    directory root_path(:data), owner: service_user(), group: service_user(), mode: 0o750
    directory root_path(:state), owner: service_user(), group: service_user(), mode: 0o750

    env_file root_path(:config, "api.env"), owner: "root", group: service_user() do
      set :mix_env, :prod
      secret :database_url, env: "DATABASE_URL"
    end

    daemon unit_name() do
      description "API"
      after_target :network_online
      wants :network_online

      service_user service_user()
      working_directory root_path(:source)
      environment_file root_path(:config, "api.env")
      exec_start [Path.join(root_path(:source), "bin/server")]
      restart :on_failure
      restart_sec 10

      sandbox :strict_app,
        resources: [memory_max: "512M", tasks_max: 256],
        sandbox: [read_write_paths: [root_path(:data), root_path(:state)]]

      listen :http, port: 4000, on: :loopback
      wanted_by :multi_user
    end
  end
end
```

`strict_app` expands to systemd hardening options such as:

- `NoNewPrivileges=`
- `PrivateTmp=`
- `PrivateDevices=`
- `ProtectSystem=strict`
- `ProtectHome=`
- `ProtectKernelTunables=`
- `ProtectKernelModules=`
- `ProtectControlGroups=`
- `RestrictAddressFamilies=`
- `RestrictSUIDSGID=`
- `LockPersonality=`
- `SystemCallArchitectures=native`

Use the `sandbox:` option to override sandbox fields and `resources:` to set resource controls. For less strict services, use `sandbox :web_service` or `sandbox :vibe_dev`.

Lower-level systemd directives are still available through `unit`, `service`, `run`, `install`, and specific helpers such as `after_target`, `wants`, `requires`, `read_write_paths`, and `hardening`.
