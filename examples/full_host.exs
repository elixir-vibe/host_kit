use HostKit.DSL, providers: [HostKit.Providers.Caddy]

project :prod do
  host :app, at: "app.example.com" do
    ssh do
      user("root")
      identity_file(Path.expand("~/.ssh/id_ed25519"))
      accept_hosts(true)
      retry(attempts: 3)
    end
  end

  provider :caddy, HostKit.Providers.Caddy do
    set(:sites_dir, "/etc/caddy/sites")
  end

  bootstrap do
    package(:ca_certificates)
    package(:build_essential, as: "build-essential", update: true)

    mise do
      tool(:erlang, "29.0.2")
      tool(:elixir, "1.20.1")
    end
  end

  service :api do
    account(system: true)
    storage(:data, mode: 0o750)

    env :runtime do
      set(:mix_env, :prod)
      secret(:database_url, env: "DATABASE_URL")
    end

    daemon do
      description("API service")
      env(:runtime)
      exec(["/opt/api/bin/server"])

      # Container-like isolation without a Docker daemon.
      isolate do
        memory_max("512M")
        writable(:data)
        network(:loopback)
      end

      listen(:http, port: 4000)
    end

    caddy_site "api.example.com" do
      encode([:zstd, :gzip])
      reverse_proxy(:http)
    end
  end
end
