# Remote bootstrap and plan artifacts

HostKit's remote flow is designed for machines that may not have Elixir, Mix, or application runtimes installed yet.

The control machine runs HostKit. The target machine only needs SSH and a supported package manager.

## Declare the host

```elixir
use HostKit.DSL

project :prod do
  host :server, at: "203.0.113.10" do
    ssh do
      user "root"
      password secret_env("HOSTKIT_SSH_PASSWORD")
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

Identity-file auth is preferred when available:

```elixir
ssh do
  user "root"
  identity_file Path.expand("~/.ssh/id_ed25519")
  accept_hosts true
end
```

## Package resolution and locks

HostKit resolves semantic package names to target package names using Repology. Write a package lock when planning for repeatable applies:

```sh
mix host_kit.plan --host server \
  --write-package-lock host_kit.package.lock \
  infra/config.exs
```

Apply with the lock:

```sh
mix host_kit.apply --host server \
  --package-lock host_kit.package.lock \
  --confirm \
  infra/config.exs
```

## Plan artifacts

For production, prefer a two-step artifact flow:

```sh
HOSTKIT_SSH_PASSWORD='...' mix host_kit.plan --host server \
  --package-lock host_kit.package.lock \
  --out host_kit.plan.json \
  infra/config.exs
```

Review `host_kit.plan.json`, then apply the reviewed artifact:

```sh
HOSTKIT_SSH_PASSWORD='...' mix host_kit.apply --host server \
  --plan host_kit.plan.json \
  --confirm \
  infra/config.exs
```

Artifacts include target metadata such as package manager/repository. `apply --plan` validates that metadata before applying package changes.

## Secret safety

`secret_env/1` serializes as a reference:

```json
{
  "$type": "struct",
  "module": "Elixir.HostKit.Secret",
  "fields": {
    "source": {
      "$type": "tuple",
      "items": [
        {"$type": "atom", "value": "env"},
        "HOSTKIT_SSH_PASSWORD"
      ]
    }
  }
}
```

The resolved secret value is not stored in the artifact.

## Linux integration with Incus

Create an Incus-backed target:

```sh
HOSTKIT_INCUS_SUDO=true HOSTKIT_SSH_PUBLIC_KEY=$HOME/.ssh/id_ed25519.pub \
  scripts/incus_integration_vm.sh ensure
```

Run the remote CLI integration against it:

```sh
HOSTKIT_INTEGRATION_TOOL=incus HOSTKIT_INCUS_SUDO=true \
  mix test test/integration/cli_remote_test.exs --include integration
```

Use `HOSTKIT_INCUS_TYPE=vm` for an Incus VM instead of the default container.

## Real remote validation

Copy `examples/integration_hosts.example.exs`, set the hostname/auth settings, then run:

```sh
HOSTKIT_SSH_PASSWORD='...' \
HOSTKIT_INTEGRATION_TOOL=remote \
HOSTKIT_INTEGRATION_CONFIG=examples/integration_hosts.example.exs \
mix test test/integration/cli_remote_test.exs --include integration
```
