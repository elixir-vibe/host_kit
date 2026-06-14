use HostKit.DSL, providers: [HostKit.Providers.Gatehouse]

project :gatehouse_edge do
  account(:gatehouse, system: true, home: "/var/lib/gatehouse")

  service :hello_phoenix do
    endpoint(:http, port: 4000, protocol: :http, health: "/health")
  end

  proxy :edge, provider: :gatehouse, path: "/etc/gatehouse/config.exs" do
    service :app do
      host("app.example.com")
      target(:main, to: endpoint(:hello_phoenix, :http), active: true)
    end
  end

  gatehouse(:edge,
    release_path: "/opt/gatehouse",
    config_path: "/etc/gatehouse/config.exs",
    state_path: "/var/lib/gatehouse/state.etf",
    run_as: account(:gatehouse)
  )
end
