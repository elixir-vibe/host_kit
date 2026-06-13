# Changelog

## Unreleased

- Added HostKit host-based CLI targeting with `mix host_kit.plan --host NAME config.exs` and `mix host_kit.apply --host NAME ...`.
- Added host SSH DSL settings, including environment-backed control-plane secrets via `secret_env/1`.
- Added inspectable plan/apply artifacts and package lock workflow.
- Added Repology-backed semantic package resolution with cache/rate-limit support.
- Added Incus integration helper for Linux-native remote bootstrap tests.
- Added `mise` bootstrap resources for BEAM tool installation.
