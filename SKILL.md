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
- Caddy/Gatus/provider-specific config through existing provider DSL
- backups, restore inputs, monitoring, and readiness checks
- externally managed secret files represented as redacted resources

## Operating rules

- Plan before apply unless the user explicitly asks for emergency action.
- Change HostKit source, not generated live files.
- Use existing DSL and existing project patterns; do not invent new DSL while operating an end-user project.
- Avoid raw systemd/YAML/shell escape hatches when an existing HostKit DSL form already exists.
- Do not hardcode repeated absolute paths. Use declared roots and .
- Do not render or commit secrets. Model external secret files as redacted.
- Do not introduce stack drift: no dependency, web server, database, queue, storage, or deployment-model swaps without explicit approval.
- Keep operational logic Elixir-first when practical; shell belongs at OS/tool boundaries.

## Standard workflow

1. Read the relevant project instructions and HostKit config.
2. Find existing examples in the same config before editing.
3. Edit HostKit source (, , docs), not live generated files.
4. Run syntax/format checks.
5. Run  for the smallest relevant service set.
6. Apply only after the plan is understood.
7. Verify service state and public/internal health.
8. Commit/push source changes and update docs if bootstrap/recovery behavior changed.

## Common commands



Use the consuming project’s exact paths. Production configs often live at paths such as ; do not assume the current directory is the deployment checkout.

## Paths

Declare roots once in the project and use  everywhere:



Inside a service, conventional roots are service-scoped:



Global/custom roots remain global:



When a path is reused, bind it once near the declaration:



Store managed payloads under a target-shaped  tree, then read them from the config helper:



## Files and secrets

For managed static files:



For externally provisioned secret-bearing files that HostKit must not render:



Redacted content is for existence/metadata/drift modeling. It is intentionally not renderable.

## Systemd

Prefer existing high-level systemd DSL in configs:



For periodic oneshot work:



Use raw , , , , or  only when the low-level systemd directive itself is the requirement or no higher-level DSL exists.

## Monitoring

Prefer one alerting surface. If Gatus is the alerting dashboard, push internal host checks into Gatus external endpoints instead of sending separate Telegram alerts from another script.

Good shape:



Keep Gatus private unless the project explicitly documents protected public exposure.

## Red flags

Stop and ask before proceeding if you are about to:

- hand-edit a live generated config/unit/script as the lasting fix
- add hardcoded absolute paths repeatedly instead of 
- bypass existing HostKit DSL with raw systemd/YAML/shell
- render redacted or secret values into source
- install new server runtimes or production dependencies to work around a blocker
- leave a manual step undocumented
- make Gatus/status dashboards public without explicit protection and docs
