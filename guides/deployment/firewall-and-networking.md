# Firewall and networking

HostKit can model host firewall policy, workspace egress policy, service listeners, and systemd network restrictions.

```elixir
use HostKit.DSL

project :prod do
  firewall do
    allow tcp: 22, from: :any
    allow tcp: [80, 443], from: :any
    allow tcp: 9100, from: {10, 44, 0, 0, 24}
    deny :all
  end

  service :api do
    daemon "api.service" do
      exec_start ["/opt/api/bin/server"]

      listen :http, port: 4000, on: :loopback

      network_policy deny: :all,
                     allow: [:loopback]
    end
  end
end
```

Firewall policy renders to nftables. `network_policy` compiles into systemd service options such as `IPAddressDeny=`, `IPAddressAllow=`, and `RestrictAddressFamilies=`.

## Host-scoped firewall

Firewall policy can also live inside a host declaration:

```elixir
host :prod, hostname: "app.example.com" do
  firewall do
    allow tcp: 22, from: :any
    allow tcp: [80, 443], from: :any
    deny :all
  end
end
```

## Named listeners

Named listeners keep provider integrations decoupled from port literals:

```elixir
use HostKit.DSL, providers: [HostKit.Providers.Caddy]

project :prod do
  service :api do
    daemon "api.service" do
      exec_start ["/opt/api/bin/server"]
      listen :http, port: 4000, on: :loopback
    end

    caddy_site :api, "api.example.com" do
      reverse_proxy listener(:http)
    end
  end
end
```

## Workspace egress

Workspace services can express outbound policy separately from host ingress:

```elixir
workspace :blog, owner: :alice do
  service :preview do
    egress deny: :private, allow: [tcp: 443]
  end
end
```

This gives HostKit enough information to render firewall/network policy and to audit what each service or workspace is expected to reach.
