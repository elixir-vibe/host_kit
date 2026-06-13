# Timers and jobs

HostKit can declare persistent systemd services and scheduled systemd timers.

```elixir
use HostKit.DSL

project :prod do
  service :maintenance do
    job "backup.service" do
      description "Backup app data"
      service_user "backup"
      working_directory "/srv/app"
      exec_start ["/opt/app/bin/backup"]
      sandbox :strict_app,
        sandbox: [read_write_paths: ["/srv/backups"]]
    end

    schedule "backup.timer" do
      description "Run backups every hour"
      every "hourly"
      persistent true
      wanted_by :timers
    end
  end
end
```

`job` is a service-oriented alias for a oneshot-ish systemd service declaration. `schedule` declares the matching timer.

Lower-level forms are available when you want explicit sections:

```elixir
systemd_service "cleanup.service" do
  unit description: "Cleanup old files"
  service type: :oneshot,
          user: "cleanup",
          exec_start: ["/opt/app/bin/cleanup"]
end

systemd_timer "cleanup.timer" do
  unit description: "Daily cleanup"
  timer on_calendar: "daily",
        persistent: true
  install wanted_by: ["timers.target"]
end
```

Convenience helpers:

- `every "hourly"` sets a calendar interval.
- `persistent true` asks systemd to catch up missed runs.
- `on_boot "5m"` schedules relative to boot.
- `wanted_by :timers` installs into `timers.target`.

Timers compile to normal `HostKit.Systemd.Timer` structs and can be planned/applied like other resources.
