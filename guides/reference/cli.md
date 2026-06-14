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
- `--last` — read the latest tracked run and use its referenced up plan artifact.
- `--runs-root PATH` — override the HostKit runs root for `--last` / `--run`.
- `--run RUN_ID` — build a down plan from a specific tracked run.
- `--out PATH` — write the generated down plan artifact.
- `--only type:name` — include only selected resources.
- `--except type:name` — exclude selected resources.
- `--format text|inspect` — output format.

Examples:

```sh
mix host_kit.down host_kit.plan.json --out host_kit.down.plan.json
mix host_kit.down --last --runs-root /var/lib/hostkit/runs --out host_kit.down.plan.json
mix host_kit.down --run 20260614-101148-demo-up --runs-root /var/lib/hostkit/runs --out host_kit.down.plan.json
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
- `--track` — write a minimal run record after apply.
- `--runs-root PATH` — override the HostKit runs root for tracked applies.
- `--backups-root PATH` — override the HostKit backup payload root for tracked applies.
- `--quiet` — print only high-level progress and failures.
- `--verbose` — print all apply events, including skipped changes.

Examples:

```sh
mix host_kit.apply --host prod --plan host_kit.plan.json --confirm infra/config.exs
mix host_kit.apply --host prod --package-lock host_kit.package.lock --dry-run infra/config.exs
```

## `mix host_kit.runs`

List minimal tracked run records. Records are written by `mix host_kit.apply --track`.

```sh
mix host_kit.runs [options] [config.exs]
```

Common options:

- `--host NAME` — list runs from a declared remote host.
- `--remote HOST` — raw SSH target escape hatch.
- `--runs-root PATH` — override the HostKit runs root.
- `--format text|json|inspect` — output format.
- `--verbose` — include artifact and backup paths in text output.
- `--latest` — show only the latest run.
- `--id RUN_ID` — show one run by id.
- `--prune --keep N` — remove older run records plus copied artifact/backup payload directories, keeping the newest `N` runs.

Examples:

```sh
mix host_kit.apply --host prod --track --plan up.plan.json --confirm infra/config.exs
mix host_kit.runs --host prod infra/config.exs
mix host_kit.runs --host prod --verbose infra/config.exs
mix host_kit.runs --host prod --latest --verbose infra/config.exs
mix host_kit.runs --host prod --prune --keep 20 infra/config.exs
```

## Target selection

Prefer `--host` with a declared host:

```elixir
host :prod, at: "host.example" do
  ssh do
    user "root"
    identity_file Path.expand("~/.ssh/id_ed25519")
    retry attempts: 3, base_delay: 250, max_delay: 2_000
  end
end
```

`ssh retry: ...` retries SSH connection establishment for flaky transport before apply work starts; it does not rerun arbitrary remote commands after they may have reached the host.

Raw `--remote` flags remain available for ad-hoc usage, but they are less reproducible than checked-in `.exs` host config.
