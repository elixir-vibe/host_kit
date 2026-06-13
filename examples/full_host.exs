use HostKit.DSL, providers: [HostKit.Providers.Caddy]

project :prod do
  host :app do
    hostname("app.example.com")
    user("root")
    sudo(true)

    # For password-only hosts use:
    # ssh password: secret_env("HOSTKIT_SSH_PASSWORD"), silently_accept_hosts: true
    ssh(
      identity_file: Path.expand("~/.ssh/id_ed25519"),
      silently_accept_hosts: true
    )
  end

  provider :caddy, HostKit.Providers.Caddy do
    set(:sites_dir, "/etc/caddy/sites")
  end

  service :bootstrap do
    package(:ca_certificates)
    package(:build_essential, as: "build-essential", update: true)

    mise path: "/usr/local/bin/mise", system_data_dir: "/usr/local/share/mise" do
      tool(:erlang, "29.0.2")
      tool(:elixir, "1.20.1")
    end
  end

  service :api do
    system_user("api", home: "/var/lib/api")

    directory("/var/lib/api", owner: "api", group: "api", mode: 0o750)

    env_file "/etc/api/api.env", owner: "root", group: "api" do
      set(:mix_env, :prod)
      secret(:database_url, env: "DATABASE_URL")
    end

    daemon "api.service" do
      description("API service")
      service_user("api")
      working_directory("/opt/api")
      environment_file("/etc/api/api.env")
      exec_start(["/opt/api/bin/server"])
      restart(:on_failure)

      # Container-like isolation without a Docker daemon.
      sandbox(:strict_app,
        resources: [memory_max: "512M"],
        sandbox: [read_write_paths: ["/var/lib/api"]]
      )

      listen(:http, port: 4000, on: :loopback)
      wanted_by(:multi_user)
    end

    caddy_site :api, "api.example.com" do
      encode([:zstd, :gzip])
      reverse_proxy(listener(:http))
    end
  end
end
