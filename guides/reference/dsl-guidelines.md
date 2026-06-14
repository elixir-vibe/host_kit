# DSL design guidelines

HostKit DSL is for humans first. It should read like a declaration of the host, not a transcription of systemd, SSH, Caddy, or file paths. The implementation must still compile to plain inspectable structs.

## Core principles

1. **One human concept, one DSL concept.** Do not split one idea across unrelated macros. A managed runtime env file is `env`; it should not require users to pair `env_file` with `environment_file` in normal code.
2. **Context is part of the DSL.** The same word may be valid in different scopes when the human concept is the same. Example: `env :runtime do ... end` declares the env file in `service`; `env :runtime` attaches it in `daemon`.
3. **Names are logical references.** Prefer symbolic names for objects declared in the same HostKit project: `:data`, `:runtime`, `:http`. Resolve them to paths, ports, upstreams, and systemd directives at compile time.
4. **Paths are derived unless path choice is the point.** README and happy-path docs should not repeat `/var/lib/app`, `/etc/app/env`, or unit names. Use storage/env/service conventions and only expose explicit paths for overrides.
5. **Blocks group configuration. Statements declare facts.** Use `do/end` when several settings configure one concept. Use a statement for a single fact or reference.
6. **Good defaults beat required boilerplate.** Common daemons should derive the unit name and default to `multi-user.target`. Root SSH should not imply `sudo`.
7. **Escape hatches are allowed but not the happy path.** Low-level systemd directives and explicit file paths are valid for advanced guides, not the first example.

## Naming rules

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
