# Timers and jobs

HostKit can declare persistent systemd services and scheduled systemd timers.

```elixir
use HostKit.DSL

project :prod do
  service :maintenance do
    account system: true
    storage :backups, path: "/srv/backups", mode: 0o750

    job "backup.service" do
      description "Backup app data"
      service_user service_user()
      working_directory "/srv/app"
      exec ["/opt/app/bin/backup"]

      isolate do
        writable :backups
      end
    end

    schedule "backup.timer" do
      description "Run backups daily"
      daily at: ~T[02:30:00]
      jitter "15m"
      persistent true
      wanted_by :timers
    end
  end
end
```

`job` is a service-oriented alias for a oneshot-ish systemd service declaration. `schedule` declares the matching timer.

Backup jobs reuse the same concepts. Mark service storage with `backup: true`, attach service backup metadata with `backup`, then attach backup execution metadata to an existing `job`. HostKit sets the job `ExecStart` to `mix host_kit.backup.run ...`; archive creation, service stop/start, verification, checksums, manifests, and retention are implemented in Elixir modules rather than generated shell scripts.

```elixir
service :app do
  storage :state, path: "/var/lib/app", backup: true

  backup do
    consistency :stop
    verify storage_path(:state), "app.duckdb"
  end
end

service :maintenance do
  storage :backups, path: "/srv/backups", mode: 0o700

  job "app-backup" do
    backup destination: storage_path(:backups), config: "/opt/app/infra/config.exs", cwd: "/opt/host_kit" do
      include :app
      keep days: 14
    end
  end

  schedule "app-backup" do
    daily at: ~T[02:30:00]
    persistent true
  end
end
```

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

- `every "hourly"` or `every :hour` sets a simple systemd calendar interval.
- `daily at: ~T[02:30:00]` sets `OnCalendar=*-*-* 02:30:00`.
- `weekly :monday, at: "02:30"` sets a weekday calendar expression.
- `monthly day: 1, at: "02:30"` sets a day-of-month calendar expression.
- `jitter "15m"` sets `RandomizedDelaySec`.
- `repeat_after "1h"` sets `OnUnitActiveSec`.
- `after_boot "5m"` and `on_boot "5m"` set `OnBootSec`.
- `persistent true` asks systemd to catch up missed runs.
- `wanted_by :timers` installs into `timers.target`.

Raw `timer on_calendar: ...` remains available for full systemd calendar syntax.
Timers compile to normal `HostKit.Systemd.Timer` structs and can be planned/applied like other resources.
