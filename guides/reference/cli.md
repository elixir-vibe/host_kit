# CLI reference

Mix tasks are wrappers around the HostKit runtime API.

## `mix host_kit.plan`

Build and print a plan.

```sh
mix host_kit.plan [options] [config.exs]
```

Common options:

- `--host NAME` — use a host declared in the HostKit config.
- `--local` — read local state.
- `--remote HOST` — raw SSH target escape hatch.
- `--user USER` — SSH user for `--remote`.
- `--port PORT` — SSH port for `--remote`.
- `--identity-file PATH` — SSH identity file.
- `--password PASSWORD` — SSH password; prefer config secrets or `--password-env`.
- `--password-env VAR` — read raw SSH password from an environment variable.
- `--silently-accept-hosts` — accept unknown SSH host keys.
- `--sudo` — use sudo on the target.
- `--package-lock PATH` — read deterministic package resolutions.
- `--write-package-lock PATH` — write deterministic package resolutions.
- `--out PATH` — write an inspectable JSON plan artifact.
- `--repology-cache PATH` — cache directory for Repology responses.
- `--repology-cache-ttl SECONDS` — cache TTL.
- `--repology-no-cache` — disable Repology cache.
- `--format text|inspect` — output format.
- `--ignore type:name` — ignore a resource.
- `--require PATH` — load project-local DSL/support code before config.

Examples:

```sh
mix host_kit.plan --host prod infra/config.exs
mix host_kit.plan --host prod --write-package-lock host_kit.package.lock infra/config.exs
mix host_kit.plan --host prod --package-lock host_kit.package.lock --out host_kit.plan.json infra/config.exs
```

## `mix host_kit.down`

Build a down/rollback plan from an existing plan artifact. Rollback is just another plan: inspect the generated down plan, then apply it.

```sh
mix host_kit.down [options] [up.plan.json]
```

Common options:

- `--plan PATH` — read an up plan artifact.
- `--out PATH` — write the generated down plan artifact.
- `--only type:name` — include only selected resources.
- `--except type:name` — exclude selected resources.
- `--format text|inspect` — output format.

Examples:

```sh
mix host_kit.down host_kit.plan.json --out host_kit.down.plan.json
mix host_kit.apply --plan host_kit.down.plan.json --confirm
```

## `mix host_kit.apply`

Apply a plan. Requires `--dry-run` or `--confirm`.

```sh
mix host_kit.apply [options] [config.exs]
```

Common options:

- `--host NAME` — use a host declared in the HostKit config.
- `--plan PATH` — apply a previously written plan artifact.
- `--confirm` — apply changes.
- `--dry-run` — exercise apply without changing the target.
- `--package-lock PATH` — read deterministic package resolutions when planning inline.
- `--local`, `--remote`, `--user`, `--port`, `--identity-file`, `--password`, `--password-env`, `--silently-accept-hosts`, `--sudo` — same target options as `plan`.
- `--require PATH` — load project-local DSL/support code before config.

Examples:

```sh
mix host_kit.apply --host prod --plan host_kit.plan.json --confirm infra/config.exs
mix host_kit.apply --host prod --package-lock host_kit.package.lock --dry-run infra/config.exs
```

## Target selection

Prefer `--host` with a declared host:

```elixir
host :prod do
  hostname "host.example"
  user "root"
  sudo true
  ssh identity_file: Path.expand("~/.ssh/id_ed25519")
end
```

Raw `--remote` flags remain available for ad-hoc usage, but they are less reproducible than checked-in `.exs` host config.
