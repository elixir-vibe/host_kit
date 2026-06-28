# DSL design guidelines

HostKit DSL is for humans first. It should read like a declaration of the host, not a transcription of systemd, SSH, Caddy, or file paths. The implementation must still compile to plain inspectable structs.

## Public DSL stability

HostKit is still beta, but public examples should already follow the stable direction:

- use `path/2` for configured roots and service-scoped conventional paths;
- use `template/2`, `dotenv/2`, `ini/2`, and `yaml/2` for managed text/config files;
- use `symlink/2` for links instead of shell commands;
- use suffixless `daemon` / `schedule` names and let HostKit normalize unit names;
- use `argv/2` or `~SH` for simple commands, and reserve `~BASH` for real shell scripts;
- use atoms for logical references declared in the same project, and strings for generated external names/paths;
- keep provider/recipe DSLs compiling to ordinary inspectable resources.

Avoid new public docs or examples that reintroduce removed/legacy forms such as `root_path`, `path_name`, hand-written `.service` / `.timer` suffixes in high-level service DSL, or raw heredoc config files when a structured config resource fits.

## Core principles

1. **One human concept, one DSL concept.** Do not split one idea across unrelated macros. A managed runtime env file is `env`; it should not require users to pair `env_file` with `environment_file` in normal code.
2. **Context is part of the DSL.** The same word may be valid in different scopes when the human concept is the same. Example: `env :runtime do ... end` declares the env file in `service`; `env :runtime` attaches it in `daemon`.
3. **Names are logical references.** Prefer symbolic names for objects declared in the same HostKit project: `:data`, `:runtime`, `:http`. Resolve them to paths, ports, upstreams, and systemd directives at compile time.
4. **Paths are derived unless path choice is the point.** README and happy-path docs should not repeat `/var/lib/app`, `/etc/app/env`, or unit names. Use storage/env/service conventions and only expose explicit paths for overrides.
5. **Blocks group configuration. Statements declare facts.** Use `do/end` when several settings configure one concept. Use a statement for a single fact or reference.
6. **Good defaults beat required boilerplate.** Common daemons should derive the unit name and default to `multi-user.target`. Root SSH should not imply `sudo`.
7. **Escape hatches are allowed but not the happy path.** Low-level systemd directives and explicit file paths are valid for advanced guides, not the first example.

## Naming rules

Generated names belong in `HostKit.Naming`, not in individual recipes/providers. Centralize path segments, identity segments, unit names, service users, readiness names, ingress route names, and command/resource names there so user-facing DSL stays consistent.

### Use nouns for declared things

Declared project objects should be nouns:

```elixir
host :app, at: "app.example.com"
storage :data
env :runtime
service :api
```

### Use verbs for actions inside a configured thing

Inside a block, verbs express how that object behaves:

```elixir
ssh do
  user "root"
  identity_file Path.expand("~/.ssh/id_ed25519")
  accept_hosts true
end

caddy_site "api.example.com" do
  reverse_proxy :http
end
```

### Avoid leaking backend names

Do not expose backend vocabulary when the human intent is clearer:

- Prefer `env :runtime` over `environment_file "/etc/app/runtime.env"`.
- Prefer `exec [...]` over `exec_start [...]` in normal app examples.
- Prefer `isolate do ... end` over raw systemd sandbox keyword lists.
- Prefer `reverse_proxy :http` over `reverse_proxy listener(:http)`.

Backend-specific names remain acceptable in low-level reference sections.

## Blocks vs statements

Use a block when the concept has internal structure:

```elixir
host :app, at: "app.example.com" do
  ssh do
    user "root"
    identity_file Path.expand("~/.ssh/id_ed25519")
  end
end

service :api do
  env :runtime do
    secret :database_url, env: "DATABASE_URL"
  end
end
```

Use a statement when declaring one fact:

```elixir
storage :data, mode: 0o750
listen :http, port: 4000
memory_max "512M"
writable :data
```

Do not force keyword bags for nested configuration when a block is more readable:

```elixir
# Prefer
ssh do
  user "deploy"
  sudo true
  retry attempts: 3
end

# Avoid in docs
ssh user: "deploy", sudo: true, retry: [attempts: 3]
```

## Hosts vs instances

A `host` is a connection endpoint. A top-level host points at an existing target; HostKit does not create, start, stop, reset, or destroy it.

```elixir
host :prod, at: "prod.example.com" do
  ssh do
    user "deploy"
    sudo true
  end
end
```

An `instance` is a lifecycle-managed compute boundary. It selects a backend, image/kind, port exposure, nested host endpoint(s), and normal HostKit contents that should exist inside it.

```elixir
instance :demo do
  backend :incus
  image "images:ubuntu/24.04"
  kind :container
  lifecycle :ephemeral

  expose :ssh, host: 2222, guest: 22

  host :guest, at: "127.0.0.1" do
    ssh do
      user "root"
      port 2222
      accept_hosts true
    end
  end

  service :web do
    package :caddy
  end
end
```

Rule: `instance` manages the compute lifecycle; nested `host` describes how HostKit connects into that instance. Plans order the instance lifecycle resource before nested content resources, and nested content carries the selected nested host target metadata so read/apply operations execute inside the managed compute boundary. Use `target_host :name` when an instance has multiple nested host endpoints.

## References between declarations

Use symbolic names for intra-project references.

### Storage

```elixir
storage :data, mode: 0o750

isolate do
  writable :data
end
```

`:data` resolves to the declared storage path. Users should not repeat that path in `read_write_paths`.

### Env

```elixir
env :runtime do
  secret :database_url, env: "DATABASE_URL"
end

daemon do
  env :runtime
end
```

`:runtime` resolves to the managed env file. Users should not repeat the env file path.

### Listeners

```elixir
daemon do
  listen :http, port: 4000
end

caddy_site "api.example.com" do
  reverse_proxy :http
end
```

`:http` resolves to the declared loopback listener upstream.

### RPC bindings

Use `rpc` inside a service to declare exposed RPC modules, and `bind` from a caller service to declare Docker-like service bindings:

```elixir
service :catalog do
  daemon do
    listen :rpc, protocol: :rpc
  end

  rpc do
    expose Catalog.API
    expose Catalog.Admin
  end
end

service :web do
  bind :catalog
end
```

HostKit owns service names, listener/socket locations, module-level bindings, validation, caller-local binding files, and derived local socket access from `bind`. The runtime RPC protocol owns exact operation names, typespecs, and handshakes.

## Defaults

### Host / SSH

Root SSH should not set sudo:

```elixir
host :app, at: "app.example.com" do
  ssh do
    user "root"
    identity_file Path.expand("~/.ssh/id_ed25519")
  end
end
```

A non-root deploy user opts into sudo explicitly:

```elixir
ssh do
  user "deploy"
  sudo true
end
```

### Daemon

Inside `service :api`, `daemon do ... end` means:

- unit name derives from the service (`api.service` by default),
- install target defaults to `multi-user.target`,
- if the service declared `account system: true`, the daemon defaults to that account for `User=` and `Group=`,
- low-level systemd install directives are omitted from happy-path code.

Use explicit systemd directives only for non-default boot behavior.

### Mise

`mise do ... end` uses HostKit's system-wide defaults for the mise binary and data directory. Explicit `path:` and `system_data_dir:` are advanced overrides.

## Isolation naming

The README should use:

```elixir
isolate do
  memory_max "512M"
  writable :data
  network :loopback
end
```

The profile name is an internal preset selected by the DSL default. Advanced users may write `isolate :untrusted do ... end` when choosing a specific profile is the point.

Profile names must describe security intent, not implementation mechanics. Avoid vague names in first-touch docs. `:strict_app` currently means the default strict service sandbox: no new privileges, protected system/home/kernel surfaces, restricted address families, explicit writable paths, and resource controls.

## DSL layering policy

HostKit keeps low-level directives when they expose a real Linux/systemd/provider primitive that advanced users may need. Those directives are **escape hatches**, not canonical application DSL.

### Stays as escape hatch

These stay available and documented in the directive inventory/reference because they map directly to backend concepts:

- `systemd_service`, `systemd_timer`
- `unit`, `service`, `timer`, `install`
- `environment_file`, `exec_start`, `exec_stop`, `wanted_by`, `read_write_paths`
- explicit `dotenv path do ... end`
- explicit `listener(:name)` when a string upstream is required
- explicit named Caddy sites: `caddy_site :name, "host" do ... end`

### Not canonical in user-facing docs

These should not appear in README/getting-started/tutorial happy paths unless the section is explicitly about the low-level primitive:

- split host declarations; use `host :name, at: ...`
- root SSH plus `sudo true`; root does not need sudo
- `service :bootstrap`; use `bootstrap do`
- paired `env_file` and `environment_file`; use contextual `env`
- raw `exec_start`; use `exec`, and use `argv(...)` when the command has structured CLI options
- raw `wanted_by :multi_user`; `daemon do` defaults it
- raw `read_write_paths`; use `writable :storage`
- raw sandbox keyword lists; use `isolate do`
- `reverse_proxy listener(:http)`; use `reverse_proxy :http`

## README standard

The README example should showcase killer features without plumbing:

- host declaration with SSH block,
- bootstrap packages and mise runtimes,
- service account,
- named storage,
- managed env secrets,
- derived daemon,
- Docker-less isolation,
- loopback listener,
- Caddy reverse proxy by listener name.

It should not show repeated paths, explicit `multi-user.target`, `environment_file`, `read_write_paths`, or `listener(:http)` unless explaining internals.

## Directive inventory

This inventory lists the public macros exported by HostKit's core DSL, systemd DSL, Caddy provider DSL, and Elixir app recipe DSL. It is intentionally explicit so the reference does not drift from the actual directive surface.

Legend:

- **Canonical** — preferred in README and normal project examples.
- **Reference** — useful, but belongs in reference/provider/recipe docs rather than the first example.
- **Escape hatch** — low-level backend vocabulary for advanced cases.

### Core project and composition

| Directive | Level | Purpose |
| --- | --- | --- |
| `project` | Canonical | Top-level declaration that returns a `%HostKit.Project{}`. |
| `providers` | Reference | Set provider modules for the project. Prefer `use HostKit.DSL, providers: [...]` in examples. |
| `provider` | Reference | Configure one provider, such as Caddy paths. |
| `roots` | Reference | Declare project path roots. |
| `prefixes` | Reference | Declare naming prefixes for users, units, etc. |
| `tenant` | Reference | Declare a tenant and corresponding workspace scope. |
| `workspace` | Reference | Scope path and identity conventions for per-user/per-workspace services. |
| `put_in_meta` | Escape hatch | Attach arbitrary metadata to the current service. |

### Hosts, instances, and SSH

| Directive | Level | Purpose |
| --- | --- | --- |
| `host` | Canonical | Declare a named connection endpoint; top-level hosts are existing targets, nested hosts are endpoints into an instance. |
| `instance` | Canonical | Declare a lifecycle-managed compute instance with backend, image, exposed ports, nested hosts, and nested HostKit contents. |
| `backend` | Canonical | Select the implementation backend for an instance, ingress, proxy, or other backend-driven declaration. Accepts backend-neutral option syntax such as `backend :incus, sudo: true`. |
| `option` | Reference | Set a backend option inside `backend ... do`; options stay attached to the selected backend instead of leaking into generic plan/apply flags. |
| `image` | Canonical | Set the instance image. |
| `kind` | Canonical | Set the instance kind, such as `:container` or `:vm`. |
| `lifecycle` | Reference | Set instance lifecycle policy, such as `:persistent` or `:ephemeral`. Ephemeral instances are deleted in down plans; persistent instances are skipped with a warning. |
| `target_host` | Canonical | Select which nested host endpoint receives nested instance content resources when multiple nested hosts exist. |
| `expose` | Canonical | Declare an instance port exposure from host to guest. |
| `ssh` | Canonical | Configure host SSH transport as a block. |
| `user` | Canonical | SSH user inside `ssh`. |
| `identity_file` | Canonical | SSH key path inside `ssh`. |
| `password` | Reference | SSH password/secret inside `ssh`. |
| `port` | Reference | SSH port inside `ssh`. |
| `accept_hosts` | Canonical | Accept unknown host keys for bootstrap/demo environments. |
| `retry` | Canonical | SSH connection retry policy. |
| `sudo` | Reference | Enable sudo for non-root SSH users inside `ssh`. Root examples should not set it. |
| `secret_env` | Reference | HostKit control-plane secret from an environment variable. |

### Bootstrap, packages, commands, files

| Directive | Level | Purpose |
| --- | --- | --- |
| `bootstrap` | Canonical | Group host bootstrap resources without pretending they are an app service. |
| `package` | Canonical | Declare one OS package. |
| `packages` | Reference | Declare several OS packages with shared options. |
| `mise` | Canonical | Bootstrap system-wide mise and managed tools. |
| `tool` | Canonical | Declare a mise-managed tool version. |
| `directory` | Reference | Declare an explicit directory resource. Prefer `storage` for service data. |
| `file` | Reference | Declare an explicit file resource. |
| `template` | Reference | Declare an explicit EEx-rendered file resource; secret assigns are allowed as references and redacted in template assign diffs. |
| `ini` | Reference | Declare a structured INI config file resource with public and redacted entries. |
| `yaml` | Reference | Declare a structured YAML config file resource with ordered keyword data and public-path secret comparison. |
| `toml` | Reference | Declare a structured TOML config file resource with ordered keyword data and public-path secret comparison. |
| `exs` | Reference | Declare a quoted Elixir `.exs` file resource with strict placeholders. |
| `section` | Reference | Declare an INI section inside `ini do ... end`. |
| `symlink` | Reference | Declare an explicit symbolic link resource. |
| `source` | Reference | Declare a source artifact/repository. |
| `command` | Escape hatch | Low-level command resource. |
| `run` | Reference | Command resource helper; also systemd service-option helper in systemd scope. |
| `git` | Reference | Git command resource helper. |
| `bash` | Reference | Bash command resource helper. |
| `argv` | Reference | Structured argv command builder. |
| `mix` | Reference | Mix task command builder using the `:bin` convention root by default. |
| `elixir` | Reference | Elixir CLI command builder using the `:bin` convention root by default. |
| `eval` | Reference | `elixir -e` command builder using the `:bin` convention root by default; inside lifecycle blocks it supplies that block's command. |
| `before_start` | Reference | Declare a command lifecycle step that runs before service readiness/start checks. |
| `after_start` | Reference | Declare a command lifecycle step for post-start operations. |
| `before_stop` | Reference | Declare a command lifecycle step for pre-stop operations. |
| `after_stop` | Reference | Declare a command lifecycle step for post-stop operations. |

### Service conventions, storage, env

| Directive | Level | Purpose |
| --- | --- | --- |
| `service` | Canonical | Declare an application/service boundary. |
| `account` | Canonical | Declare/ref service account; `account system: true` derives the service user. |
| `release` | Reference | Emit an inspectable binary-release layout: versions directory plus current symlink. |
| `storage` | Canonical | Declare named service storage and its directory resource. |
| `env` | Canonical | Declare a managed env file in service scope; attach it in daemon scope. |
| `secret` | Canonical | Add a secret entry inside env/dotenv or structured INI config. Use `env: :redacted` for existing generated secrets that must not render. |
| `set` | Canonical | Add non-secret config inside env/dotenv, provider config, or structured INI config. |
| `service_name` | Reference | Return current service name. |
| `service_path` | Reference | Return convention-derived service path segment for the current service. |
| `service_user` | Reference | Return convention-derived service user; systemd setter in systemd scope. |
| `unit_name` | Reference | Return convention-derived systemd unit name. |
| `path` | Reference | Resolve a path under a project root; inside services, conventional service roots (`:source`, `:data`, `:state`, `:cache`, `:config`) include the service path. |
| `storage_volume` | Reference | Return named storage metadata. |
| `storage_path` | Reference | Return named storage path. |
| `writable_storage_paths` | Reference | Return paths for writable storage volumes. |
| `backup_storage` | Reference | Return storage volumes marked for backup. |
| `dotenv` | Reference | Declare a dotenv-format env file at an explicit path. Prefer contextual `env` when the file is service-scoped and attached to daemons. |
| `env_file` | Compatibility | Older name for explicit dotenv resources. Prefer `dotenv`. |

### Daemons and systemd

| Directive | Level | Purpose |
| --- | --- | --- |
| `daemon` | Canonical | Declare a persistent service unit; defaults unit name and multi-user install. |
| `exec` | Canonical | Human spelling for service command. |
| `listen` | Canonical | Declare a logical listener and systemd listen metadata in daemon scope. |
| `isolate` | Canonical | Apply default strict service isolation as a block. |
| `memory_max` | Canonical | Set memory limit inside `isolate`. |
| `writable` | Canonical | Allow a storage/path as writable inside `isolate`. |
| `network` | Canonical | Network policy inside `isolate`; currently supports `:loopback`. |
| `systemd_service` | Escape hatch | Declare a raw systemd service resource. |
| `systemd_timer` | Escape hatch | Declare a raw systemd timer resource. |
| `job` | Reference | Systemd service intended as a job. |
| `schedule` | Reference | Systemd timer helper. |
| `unit` | Escape hatch | Set raw `[Unit]` directives. |
| `systemd` | Reference | Readiness check for a systemd unit. |
| `service` | Escape hatch | Set raw `[Service]` directives in systemd scope. |
| `timer` | Escape hatch | Set raw `[Timer]` directives. |
| `install` | Escape hatch | Set raw `[Install]` directives. |
| `description` | Reference | Set unit description. |
| `after_units` | Escape hatch | Set raw systemd `After=` units. |
| `after_target` | Reference | Set `After=` using target aliases. |
| `wants` | Reference | Set `Wants=` using target aliases. |
| `requires` | Reference | Set `Requires=` using target aliases. |
| `service_group` | Reference | Set systemd service group. |
| `working_directory` | Reference | Set service working directory. |
| `environment_file` | Escape hatch | Set raw systemd env file path. Prefer `env :name`. |
| `argv` | Reference | Build inspectable argv from positional args and CLI options. |
| `exec_start` | Escape hatch | Raw systemd spelling. Prefer `exec`. |
| `exec_stop` | Reference | Set stop command. |
| `restart` | Reference | Set restart policy. |
| `restart_sec` | Reference | Set restart delay. |
| `wanted_by` | Escape hatch | Set install target. Omit for normal daemons. |
| `hardening` | Reference | Apply older hardening presets. Prefer `isolate`. |
| `read_write_paths` | Escape hatch | Raw writable paths. Prefer `writable :storage`. |
| `every` | Canonical | Timer calendar shorthand. |
| `daily` | Canonical | Typed daily timer calendar helper with `at:` time. |
| `weekly` | Canonical | Typed weekly timer calendar helper with weekday and `at:` time. |
| `monthly` | Canonical | Typed monthly timer calendar helper with `day:` and `at:`. |
| `jitter` | Reference | Set timer `RandomizedDelaySec`. |
| `repeat_after` | Reference | Set timer `OnUnitActiveSec`. |
| `persistent` | Reference | Timer persistence. |
| `after_boot` | Reference | Timer boot delay. |
| `on_boot` | Reference | Timer boot delay alias. |
| `private_network` | Reference | Override private network behavior inside `isolate`. |
| `network_policy` | Reference | Explicit network policy. Prefer `network` inside `isolate` for simple cases. |

### Ingress, proxy, readiness, observability

| Directive | Level | Purpose |
| --- | --- | --- |
| `ingress` | Reference | Declare provider-neutral ingress. |
| `server` | Reference | Declare ingress server block. |
| `tls` | Reference | Set ingress/proxy TLS mode. |
| `route` | Reference | Declare ingress route. |
| `proxy` | Reference | Configure generic proxy or proxy resource depending on arity/context. |
| `http` | Reference | Readiness HTTP check or proxy listener depending on context. |
| `https` | Reference | Proxy HTTPS listener. |
| `state` | Reference | Proxy state path. |
| `acme` | Reference | Proxy ACME config. |
| `balance` | Reference | Proxy balancing policy. |
| `health` | Reference | Proxy health check. |
| `drain` | Reference | Proxy drain timeout. |
| `target` | Reference | Proxy upstream target. |
| `ready` | Reference | Declare readiness checks. |
| `endpoint` | Reference | Declare or reference service endpoints. |
| `listener` | Reference | Resolve listener upstream. Prefer symbolic references in provider DSLs. |
| `monitor` | Reference | Attach monitor checks. |
| `observability` | Reference | Group observability declarations. |
| `telemetry` | Reference | Attach telemetry metadata/config. |
| `logs` | Reference | Attach log metadata/config. |
| `preview` | Reference | Compose listener, Caddy preview, monitor, telemetry, and logs. |

### Firewall, workspace, agents

| Directive | Level | Purpose |
| --- | --- | --- |
| `firewall` | Reference | Declare firewall policy. |
| `allow` | Reference | Add allow firewall rule. |
| `deny` | Reference | Add deny firewall rule. |
| `egress` | Reference | Service egress policy. |
| `inside` | Reference | Declare checks intended to run inside a workspace sandbox. |
| `inside_monitor` | Reference | Add an inside-sandbox monitor. |
| `agent` | Reference | Declare default workspace agent service. |
| `workspace_agent` | Reference | Alias for workspace agent declaration. |

### Caddy provider

| Directive | Level | Purpose |
| --- | --- | --- |
| `caddy_site` | Canonical | Declare a Caddy site. README form is `caddy_site "host" do ... end`. |
| `reverse_proxy` | Canonical | Proxy to a listener symbol, endpoint, string upstream, or upstream list. |
| `encode` | Reference | Add Caddy encoding directive. |
| `root` | Reference | Add Caddy root directive. |
| `file_server` | Reference | Add Caddy file server directive. |

### Gatus provider

| Directive | Level | Purpose |
| --- | --- | --- |
| `gatus_config` | Reference | Declare a structured Gatus YAML config resource. |
| `web` | Reference | Set Gatus web listener config inside `gatus_config`. |
| `gatus_storage` | Reference | Set Gatus storage config without conflicting with core `storage`. |
| `telegram_alerting` | Reference | Set Gatus Telegram alerting config. |
| `default_alert` | Reference | Set Telegram default alert options. |
| `gatus_endpoint` | Reference | Add a Gatus endpoint without conflicting with core `endpoint`. |
| `gatus_endpoints` | Reference | Add pre-rendered Gatus endpoints, typically from `HostKit.Providers.Gatus.endpoints_from_monitors/2`. |
| `gatus_monitor_endpoints` | Reference | Add Gatus endpoints generated from previously declared core monitor metadata. |

### Elixir app recipe

| Directive | Level | Purpose |
| --- | --- | --- |
| `elixir_app` | Reference | Compose source, runtime, release, env, systemd, and optional Caddy for an Elixir app. |
| `source` | Reference | Recipe source config. |
| `phoenix` | Reference | Phoenix-specific recipe config. |
| `runtime` | Reference | Runtime config. |
| `release` | Reference | Release config. |
| `caddy` | Reference | Recipe Caddy config. |
| `ecto` | Reference | Ecto migration/rollback config. |
| `repo` | Reference | Ecto repo entry. |
| `mix` | Reference | Mix command entry for recipe operations. |

### OTP release recipe

| Directive | Level | Purpose |
| --- | --- | --- |
| `otp_release` | Reference | Consume a BEAM-native OTP release ETF artifact manifest and emit ordinary deployment resources. |
