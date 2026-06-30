---
name: hostkit
description: Use HostKit to model, plan, apply, audit, and recover Linux host desired state from existing HostKit configs. Use when working with HostKit-managed deployments, infra/config.exs, systemd/services, files, secrets, monitoring, backups, bootstrap, drift, or disaster recovery.
---

# HostKit

Use this skill when operating or editing a HostKit-managed host or project. HostKit configs are the source of truth for host state; live server edits are temporary inspection/emergency actions and must be reconciled back into HostKit.

## What HostKit is for

HostKit models Linux host desired state in Elixir and produces inspectable plans before applying changes. Typical managed state includes:

- directories, files, symlinks, templates, and structured config files
- system users/groups and service accounts
- systemd daemons, oneshot jobs, and timers
- releases and current symlinks
- provider-managed configs through existing provider DSL
- backups, restore inputs, monitoring, and readiness checks
- externally managed secret files represented as redacted resources

## Operating rules

- Plan before apply unless the user explicitly asks for emergency action.
- Change HostKit source, not generated live files.
- Use existing DSL and existing project patterns; do not invent new DSL while operating an end-user project.
- Avoid raw systemd/YAML/shell escape hatches when an existing HostKit DSL form already exists.
- Do not hardcode repeated absolute paths. Use declared roots and `path/2`.
- Do not render or commit secrets. Model external secret files as redacted.
- Do not introduce stack drift: no dependency, web server, database, queue, storage, or deployment-model swaps without explicit approval.
- Keep operational logic Elixir-first when practical; shell belongs at OS/tool boundaries.

## Standard workflow

1. Read the relevant project instructions and HostKit config.
2. Find existing examples in the same config before editing.
3. Edit HostKit source (`infra/config.exs`, `infra/files/`, docs), not live generated files.
4. Run syntax/format checks.
5. Run `host_kit.plan` for the smallest relevant service set.
6. Apply only after the plan is understood.
7. Verify service state and public/internal health.
8. Commit/push source changes and update docs if bootstrap/recovery behavior changed.

## Common commands

```bash
# Plan a whole local host
mix host_kit.plan infra/config.exs --local --sudo

# Plan one or more services
mix host_kit.plan infra/config.exs --local --sudo --service monitoring

# Apply with run tracking
mix host_kit.apply infra/config.exs --local --sudo --confirm --track --service monitoring

# Inspect current resources declared by a config
mix host_kit.read infra/config.exs --local --sudo

# Build/apply rollback from tracked run when needed
mix host_kit.runs --verbose
mix host_kit.down --last --out down.plan.json
mix host_kit.apply --plan down.plan.json --confirm
```

Use the consuming project’s exact paths. Production configs often live at paths such as `/opt/app/src/app/infra/config.exs`; do not assume the current directory is the deployment checkout.

## Paths

Declare roots once in the project and use `path/2` everywhere:

```elixir
roots source: "/opt/app/src",
      data: "/srv/app",
      state: "/var/lib/app",
      config: "/etc/app",
      opt: "/opt/app",
      sbin: "/usr/local/sbin"
```

Inside a service, conventional roots are service-scoped:

```elixir
service :api do
  path(:data)              # /srv/app/api
  path(:config, "env")    # /etc/app/api/env
end
```

Global/custom roots remain global:

```elixir
path(:opt, "lib/app/health.exs")
path(:sbin, "app-tool")
```

When a path is reused, bind it once near the declaration:

```elixir
health_script = path(:opt, "lib/app/health.exs")
file health_script, content: Files.read("opt/app/lib/app/health.exs")
```

Store managed payloads under a target-shaped `files/root` tree, then read them from the config helper:

```text
infra/files/root/opt/app/lib/app/health.exs
infra/files/root/usr/local/sbin/app-tool
```

## Files and secrets

For managed static files:

```elixir
file path(:sbin, "app-tool"),
  owner: "root",
  group: "root",
  mode: 0o755,
  content: Files.read("usr/local/sbin/app-tool")
```

For externally provisioned secret-bearing files that HostKit must not render:

```elixir
file path(:config, "s3.env"),
  owner: "root",
  group: service_user(),
  mode: 0o640,
  content: :redacted
```

Redacted content is for existence/metadata/drift modeling. It is intentionally not renderable.

## Systemd

Prefer existing high-level systemd DSL in configs:

```elixir
daemon "app-worker" do
  description "Run app worker"
  after_target :network_online
  wants :network_online
  exec [path(:opt, "current/app/bin/app"), "worker"]
  restart :always
end
```

For periodic oneshot work:

```elixir
daemon "app-health-push", install: [] do
  description "Push app health"
  after_units ["app.service"]
  wants ["app.service"]
  run type: :oneshot,
      environment_file: path(:config, "env"),
      exec_start: ["/usr/bin/env", "elixir", health_script]
end

schedule "app-health-push" do
  description "Push app health periodically"
  after_boot "2min"
  repeat_after "15min"
  persistent true
  jitter "1min"
  wanted_by :timers
end
```

Use raw `unit`, `service`, `timer`, `systemd_service`, or `systemd_timer` only when the low-level systemd directive itself is the requirement or no higher-level DSL exists.

## Monitoring

Prefer one alerting surface. If Gatus is the alerting dashboard, push internal host checks into Gatus external endpoints instead of sending separate Telegram alerts from another script.

Good shape:

```text
HostKit-managed timer -> Elixir health checker -> local Gatus external endpoint -> Gatus alerting
```

Keep Gatus private unless the project explicitly documents protected public exposure.

## Red flags

Stop and ask before proceeding if you are about to:

- hand-edit a live generated config/unit/script as the lasting fix
- add hardcoded absolute paths repeatedly instead of `path/2`
- bypass existing HostKit DSL with raw systemd/YAML/shell
- render redacted or secret values into source
- install new server runtimes or production dependencies to work around a blocker
- leave a manual step undocumented
- make Gatus/status dashboards public without explicit protection and docs
