use HostKit.DSL, providers: [HostKit.Providers.Gatehouse]

project :gatehouse_edge do
  account(:gatehouse, system: true, home: "/var/lib/gatehouse")

  gatehouse_release(:edge,
    source: [github: "dannote/gatehouse", ref: "main"],
    release_path: "/opt/gatehouse"
  )

  service :hello_phoenix do
    endpoint(:http, port: 4000, protocol: :http, health: "/health")
  end

  service :edge do
    ingress :web, path: "/etc/gatehouse/config.exs", state: "/var/lib/gatehouse/state.etf" do
      server ":80" do
        route host: "app.example.com" do
          proxy(to: endpoint(:hello_phoenix, :http))
        end
      end
    end
  end

  gatehouse(:edge,
    release_path: "/opt/gatehouse",
    config_path: "/etc/gatehouse/config.exs",
    state_path: "/var/lib/gatehouse/state.etf",
    run_as: account(:gatehouse)
  )
end
