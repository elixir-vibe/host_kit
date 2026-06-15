# Changelog

## Unreleased

- Added structured, JSON Patch-backed plan diffs for `dotenv/2`, `ini/2`, `yaml/2`, and template assign metadata, with human-readable public changes and separate redacted paths/assigns in plan output/artifacts.
- Added provider-neutral endpoint projection for HTTP monitor metadata and a thin Gatus provider DSL that emits ordinary structured YAML config resources.
- Added down-plan coverage summaries to generated down plans and `mix host_kit.down` output.

## v0.1.0-beta.4 - 2026-06-15

- Added `mix host_kit.read`, `mix host_kit.audit`, and `mix host_kit.facts` wrappers for runtime introspection APIs.
- Expanded `HostKit.Facts.collect/2` to return structured users, systemd failed units, and listening ports.
- Added `dotenv PATH do ... end` as the format-style explicit env-file DSL, plus redacted env-file secrets via `secret KEY, env: :redacted`, file/command secret sources, and richer safe public-value config diff output.
- Added `argv/2` for structured command-line construction with configurable CLI option styles.
- Normalized `daemon`/`job`/`schedule` unit names so suffixless names get `.service`/`.timer` and atom names use the configured unit prefix.

## v0.1.0-beta.3 - 2026-06-15

- Replaced service-scoped `root_path/2` with unified `path/2`; conventional service roots are scoped by service context, while custom/global roots remain root-relative.
- Removed the separate service path override directive; use `service :name, path: "slug"` and shared `HostKit.Naming` helpers for path/identity normalization.
- Centralized generated recipe/provider names in `HostKit.Naming`, including readiness names, ingress route names, workspace unit/user names, Elixir release names, and command/resource names.
- Added first-class EEx template resources via `template PATH, from: ..., assigns: ...`; templates are inspectable resources, render to managed files during read/apply, and reject secret assigns until redacted template diffs exist.
- Added structured config file resources via `ini/2` and `yaml/2`, including an INI block DSL with `section`/`set`, `ymlr` scalar rendering, `yaml_elixir` YAML public-path reads, secret-aware INI key/YAML path comparison for redacted values, and explicit rejection of redacted config rendering.
- Added `symlink PATH, to: TARGET` resources with local/remote read support, apply support, rollback deletion, and documentation.
- Added `target_host` for selecting a nested instance host when an instance has multiple connection endpoints.
- Documented instance backend authoring callbacks and clarified instance down-plan ordering.
- Added semantic tests for persistent/ephemeral instance rollback behavior and nested content target selection.
- Added `HostKit.Project.read/2`, `HostKit.Project.audit/2`, and `HostKit.Facts.collect/2` for runtime read/audit/introspection workflows.
- Added README and Livebook examples for structured config resources and redacted generated secrets.

## v0.1.0-beta.2 - 2026-06-14

- Added generic `instance` DSL for lifecycle-managed compute boundaries with backend selection, nested host endpoints, nested services/resources, and target-scoped content planning.
- Added Incus instance backend support for launch/start/delete, proxy port exposure, readiness checks, and demo SSH bootstrap.
- Added backend-neutral `mix host_kit.instance status|ensure|destroy INSTANCE [config.exs]` for declared instance lifecycle.
- Added declarative backend options on `backend`, including block form with `option`, without leaking backend-specific flags into generic `plan`/`apply`.
- Added instance lifecycle apply events for launch, port exposure, readiness, and SSH bootstrap progress.
- Reworked Livebook demo VM helper to use HostKit instance lifecycle and expose both Caddy and Phoenix demo ports.
- Polished Phoenix Livebook to match the explicit Target / Declare / Plan / Deploy / Verify flow with Kino summaries and no hidden apply/verify checkboxes.
- Added SSH connection retry policy via `ssh retry: ...` with apply progress events for retry start/success/exhaustion.
- Added negative-path coverage for failed initial SSH connection and mid-apply transport failure handling.
- Improved plan/read-error formatting and compact Inspect output for plans, changes, and common resources.

## v0.1.0-beta.1

- Included Livebook demos and internal architecture guide in Hex package docs.

## v0.1.0-beta.0

Initial beta release.

- Added HostKit host-based CLI targeting with `mix host_kit.plan --host NAME config.exs` and `mix host_kit.apply --host NAME ...`.
- Added host SSH DSL settings, including environment-backed control-plane secrets via `secret_env/1`.
- Added inspectable plan/apply artifacts and package lock workflow.
- Added Repology-backed semantic package resolution with cache/rate-limit support.
- Added Incus integration helper for Linux-native remote bootstrap tests.
- Added `mise` bootstrap resources for BEAM tool installation.
