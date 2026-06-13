# Workspaces and tenants

Workspaces model per-user development sandboxes on a shared host. They compose ordinary HostKit resources with naming, paths, network policy, previews, and an optional workspace agent.

```elixir
use HostKit.DSL, providers: [HostKit.Providers.Caddy]

project :dev_host do
  roots data: "/srv/workspaces", state: "/var/lib/workspaces", config: "/etc/workspaces"
  prefixes user: "ws-", unit: "ws-"

  tenant :alice, quota: [memory: "4G"] do
    agent port: 4173
  end

  workspace :blog, owner: :alice do
    service :preview do
      directory root_path(:data), mode: :private_dir

      daemon unit_name() do
        service_user service_user()
        working_directory root_path(:data)
        exec_start ["/usr/bin/env", "mix", "phx.server"]
        sandbox :vibe_dev
        listen :http, port: 4000, on: :loopback
      end

      preview :http, port: 4000, domain: "alice-blog.dev.example.com"

      inside do
        monitor :mix, task: "test", every: "5m"
        monitor :git, clean: true
      end
    end
  end
end
```

Useful pieces:

- `tenant` declares an owner and can install a workspace agent.
- `workspace` scopes paths, identity names, and unit names for sandboxed work.
- `agent`/`workspace_agent` declare the agent service boundary.
- `preview` expands to listener/provider metadata for preview routes.
- `inside` and `inside_monitor` describe checks intended to run inside the sandbox.
- Ordinary HostKit DSL still works inside a workspace: `directory`, `daemon`, `sandbox`, `listen`, `monitor`, and provider resources.

Workspaces are intentionally inspectable. They are not a separate runtime system hidden behind opaque state; they compile to HostKit services/resources plus metadata.
