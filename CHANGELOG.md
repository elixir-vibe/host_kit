# Changelog

## Unreleased

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
