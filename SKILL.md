---
name: hostkit-config-authoring
description: Write, review, and migrate HostKit desired-state configs using current HostKit DSL conventions.
---

# HostKit config authoring

Use this skill when writing or reviewing HostKit project configs such as `infra/config.exs`, examples, deployment guides, and executable snippets.

## Core principles

- HostKit configs are executable Elixir, but should read as declarative desired state.
- Prefer the public DSL over ad hoc helper code.
- Keep declarations inspectable: DSL must compile to ordinary HostKit structs/resources.
- Do not hide runtime behavior in recipes, helper modules, or templates.
- Keep service and host concepts separate:
  - `host` is a connection endpoint.
  - `instance` is lifecycle-managed compute.
  - nested `host` inside `instance` is the connection endpoint into that instance.

## Paths

Use the unified `path/2` helper.

Declare project roots once:

```elixir
roots source: "/opt/toys/src",
      data: "/srv/toys",
      state: "/var/lib/toys",
      cache: "/var/cache/toys",
      config: "/etc/toys",
      opt: "/opt/toys",
      caddy: "/etc/caddy",
      systemd: "/etc/systemd/system",
      sbin: "/usr/local/sbin"
```

Then use `path/2` everywhere:

```elixir
path(:data)
path(:config, "app.ini")
path(:opt, "current/forgejo")
path(:sbin, "toys-route")
```

Inside a `service`, conventional service roots are scoped by service context:

```elixir
service :forgejo do
  path(:data)                 # /srv/toys/forgejo
  path(:config, "app.ini")    # /etc/toys/forgejo/app.ini
end
```

Custom/global roots remain root-relative, even inside a service:

```elixir
service :forgejo do
  path(:opt, "current/forgejo") # /opt/toys/current/forgejo
end
```

Do not reintroduce `root_path`. Do not create anonymous path helpers such as `opt_current.("forgejo")`; add/use project roots and `path/2` instead.

### Path expansion/resolution

`path/2` joins configured roots and children. It does not perform shell-style expansion such as `~user`, environment substitution, globbing, or realpath resolution. If a root really needs expansion, make that explicit in the config:

```elixir
roots local_cache: Path.expand("~/.cache/hostkit-demo")
```

Prefer absolute roots for production configs.

## RPC service bindings

Use `listen :rpc, protocol: :rpc` for same-host RPC listeners. With no `port:` or `socket:`, HostKit defaults to a Unix socket under the configured `:run` root and current service path, for example `/run/toys/llm-proxy/rpc.sock` when `roots run: "/run/toys"` and `service :llm_proxy, path: "llm-proxy"`.

Provider services declare broad RPC surfaces:

```elixir
service :llm_proxy, path: "llm-proxy" do
  daemon do
    listen :rpc, protocol: :rpc
  end

  rpc do
    expose :api
    expose :control
  end
end
```

Caller services declare Docker-like bindings:

```elixir
service :incant_admin, path: "incant-admin" do
  bind :llm_proxy, rpc: [:control]
end
```

HostKit owns service names, listener/socket locations, and broad surface bindings. Do not list exact operation names in HostKit; SafeRPC or another runtime handshake owns concrete ops and schemas.

## Service identity and paths

Prefer the `service` `path:` option when the on-disk slug differs from the logical service name:

```elixir
service :hex_mirror, path: "hex-mirror" do
  path(:data) # /srv/toys/hex-mirror
end
```

Use logical service names for readability. Use `path:` only when an existing external path/unit/user convention requires a different path segment. Do not add a separate directive for this concept.

When adding recipes, providers, workspace helpers, readiness checks, ingress renderers, or generated resource names, use `HostKit.Naming` instead of hand-rolled string replacement/interpolation for path, identity, unit, user, readiness, route, or command names. Prefer suffixless `daemon`/`schedule` names; HostKit normalizes `.service` and `.timer`.

## Files and templates

Prefer managed file payloads under a target-shaped hierarchy:

```text
infra/files/root/usr/local/sbin/tool
infra/files/root/etc/caddy/Caddyfile
```

Read them through a tiny config-local file helper, for example:

```elixir
defmodule Infra.Files do
  @root Path.expand("files/root", __DIR__)
  def read(path), do: File.read!(Path.join(@root, path))
end

file path(:sbin, "tool"), content: Infra.Files.read("usr/local/sbin/tool")
```

Prefer format-specific resources for dotenv/INI/YAML when the file is naturally data, especially service config such as env files, Forgejo `app.ini`, and Gatus YAML. Use `Keyword` syntax for ordered config data:

```elixir
dotenv path(:config, "env"), owner: "root", group: service_user(), mode: 0o640 do
  set "MIX_ENV", "prod"
  secret "GENERATED_TOKEN", env: :redacted
end

ini path(:config, "app.ini"), owner: "root", group: service_user(), mode: 0o640 do
  set "APP_NAME", "elixir.toys git"

  section "server" do
    set "DOMAIN", "git.elixir.toys"
    set "ROOT_URL", "https://git.elixir.toys/"
    secret "LFS_JWT_SECRET", env: :redacted
  end
end

yaml path(:config, "gatus.yaml"),
  content: %{
    "storage" => %{"type" => "sqlite", "path" => path(:state, "gatus.db")},
    "endpoints" => [
      %{"name" => "Forgejo", "url" => "https://git.elixir.toys", "conditions" => ["[STATUS] == 200"]}
    ]
  }
```

Use first-class EEx templates for deterministic rendered text files with small assign maps:

```elixir
template path(:config, "app.ini"),
  from: "templates/app.ini.eex",
  assigns: %{
    domain: "git.elixir.toys",
    data_dir: path(:data)
  },
  owner: "root",
  group: service_user(),
  mode: 0o640
```

`from:` paths in DSL configs are resolved relative to the declaring config file. Runtime structs may use absolute `from:` paths or inline `source:`. Templates, dotenv files, and structured config resources are first-class resources in plans and render to ordinary managed files during read/apply. Secret/redacted env/config values compare only public dotenv entries, INI keys, or YAML paths during plan reads; `:redacted` values are intentionally not renderable for apply. Secret sources support `env:`, `file:`, and `command:`. Template assigns containing secrets or `:redacted` are rejected until redacted template diffs exist. Use `argv/2` for long structured CLI commands instead of raw flag lists.

Keep templates inspectable and deterministic. Do not hide runtime behavior or shell workflows in templates. Do not commit secrets; use `content: :redacted` for existing secret-bearing files managed elsewhere, and avoid passing raw secrets as template assigns until redacted template diffs are explicitly supported.

## Symlinks

Use first-class symlink resources for current-release pointers:

```elixir
symlink path(:opt, "current/forgejo"),
  to: path(:opt, "releases/forgejo/15.0.3"),
  owner: "root",
  group: "root"
```

Do not model symlinks as directories or command-only operations.

## Systemd and services

Prefer human service DSL for ordinary daemons:

```elixir
daemon do
  exec [path(:opt, "current/app/bin/app"), "start"]
  isolate do
    writable :data
    network :loopback
  end
end
```

Use raw `systemd_service`, `unit`, `service`, `timer`, and `read_write_paths` only when exact low-level systemd state is the point.

For existing production units, first model the current unit exactly and require a no-op plan before making improvements.

## Instances

Use `instance`, not `machine`, for lifecycle-managed compute.

```elixir
instance :demo do
  backend :incus
  image "images:ubuntu/24.04"
  kind :container
  lifecycle :ephemeral

  host :guest, at: "127.0.0.1" do
    ssh do
      user "root"
      port 2222
      accept_hosts true
    end
  end
end
```

Use `backend`, not `with:`, for implementation selection. Provider registration/config and backend selection are different concepts.

## Tests and snippets

Do not build HostKit DSL snippets with interpolated strings. Use quoted AST with `unquote` or plain runtime structs/APIs:

```elixir
Code.eval_quoted(
  quote do
    use HostKit.DSL

    project :demo do
      symlink unquote(link), to: unquote(target)
    end
  end
)
```

Prefer semantic tests that validate resources/plans over regex style checks.

## Migration workflow

For real hosts:

1. Model current state first.
2. Run read-only plan.
3. Require `0 create, 0 update, 0 delete, 0 read errors` before refactoring behavior.
4. Make one small slice at a time.
5. Commit each stable no-op slice separately.
6. Do not apply unless explicitly approved.

On the target host itself, prefer local read-only planning:

```sh
mix host_kit.plan /path/to/infra/config.exs --local --sudo
```

Remote planning is for off-host control planes and depends on HostKit SSH credentials, not OpenSSH/tssh control sockets.

## Keep this skill current

When HostKit DSL, resource semantics, path conventions, file/template behavior, instance behavior, or config-writing conventions change, update this `SKILL.md` in the same change.
