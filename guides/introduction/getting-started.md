# Getting started

HostKit declarations are ordinary `.exs` files. The DSL evaluates to plain HostKit structs; evaluation does not apply changes.

## Install

Add HostKit to a Mix project while it is unreleased or path-based in this workspace:

```elixir
def deps do
  [
    {:host_kit, path: "../host_kit"}
  ]
end
```

Then fetch deps:

```sh
mix deps.get
```

## Create a host config

```elixir
# infra/config.exs
use HostKit.DSL

project :demo do
  host :local_vm, at: "192.0.2.10" do
    ssh do
      user "root"
      identity_file Path.expand("~/.ssh/id_ed25519")
      accept_hosts true
    end
  end

  bootstrap do
    package :ca_certificates
    package :curl

    mise do
      tool :erlang, "29.0.2"
      tool :elixir, "1.20.1"
    end
  end
end
```

## Plan

```sh
mix host_kit.plan --host local_vm infra/config.exs
```

For deterministic package resolution, write a lock file:

```sh
mix host_kit.plan --host local_vm \
  --write-package-lock host_kit.package.lock \
  infra/config.exs
```

## Review a plan artifact

```sh
mix host_kit.plan --host local_vm \
  --package-lock host_kit.package.lock \
  --out host_kit.plan.json \
  infra/config.exs
```

`host_kit.plan.json` is JSON, not an opaque binary. Review it before apply.

## Apply

```sh
mix host_kit.apply --host local_vm \
  --plan host_kit.plan.json \
  --confirm \
  infra/config.exs
```

Use `--dry-run` instead of `--confirm` to exercise the apply path without changing the target.

## Secrets

Control-plane secrets are represented as references:

```elixir
ssh do
  user "root"
  password secret_env("HOSTKIT_SSH_PASSWORD")
  accept_hosts true
end
```

HostKit resolves the environment variable only when opening the SSH connection. Plan artifacts contain `HOSTKIT_SSH_PASSWORD`, not the password value.

Target application env files use contextual `env` declarations:

```elixir
service :app do
  env :runtime do
    set :mix_env, :prod
    secret :database_url, env: "DATABASE_URL"
  end

  daemon do
    env :runtime
    exec ["/opt/app/bin/server"]
  end
end
```

## Next steps

- [Remote bootstrap and plan artifacts](../deployment/remote-bootstrap.md)
- [CLI reference](../reference/cli.md)
- [Full DSL/reference notes](../reference/full-reference.md)
