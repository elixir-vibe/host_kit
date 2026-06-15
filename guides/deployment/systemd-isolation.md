# Systemd isolation

HostKit is designed to make Docker optional for many single-host services. You can run each service as its own Unix user, give it explicit writable paths, wire managed env files, restrict network/address families, and apply systemd sandboxing/resource limits.

```elixir
use HostKit.DSL

project :prod do
  roots source: "/opt/apps", data: "/srv/apps", state: "/var/lib/apps", config: "/etc/apps"
  prefixes user: "app-", unit: "app-"

  service :api do
    account system: true
    storage :data, mode: 0o750
    storage :state, mode: 0o750

    env :runtime do
      set :mix_env, :prod
      secret :database_url, env: "DATABASE_URL"
    end

    daemon do
      description "API"
      after_target :network_online
      wants :network_online
      working_directory path(:source)
      env :runtime
      exec [Path.join(path(:source), "bin/server")]
      restart :on_failure
      restart_sec 10

      isolate do
        memory_max "512M"
        writable :data
        writable :state
        network :loopback
      end

      listen :http, port: 4000
    end
  end
end
```

`isolate do ... end` applies HostKit's default strict app sandbox. It expands to systemd hardening options such as:

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

Use `isolate :profile do ... end` only when selecting a specific isolation profile is the point. Lower-level systemd directives remain available through `unit`, `service`, `run`, `install`, and specific helpers such as `after_target`, `wants`, `requires`, `read_write_paths`, and `hardening`.
