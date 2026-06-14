defmodule HostKit.GatehouseRecipeTest do
  use ExUnit.Case, async: true

  test "gatehouse_release recipe emits source, mise, build, and install resources" do
    project =
      Code.eval_string("""
      use HostKit.DSL, providers: [HostKit.Providers.Gatehouse]

      project :edge do
        gatehouse_release :edge,
          source: [git: "https://github.com/elixir-vibe/gatehouse.git", ref: "master"],
          release_path: "/opt/gatehouse",
          runtime: [erlang: "29.0.2", elixir: "1.20.1"]
      end
      """)
      |> elem(0)

    resources = HostKit.Project.resources(project)

    assert Enum.any?(
             resources,
             &match?(%HostKit.Resources.Source{name: "gatehouse_edge_source"}, &1)
           )

    assert Enum.any?(resources, &match?(%HostKit.Resources.Mise{name: :gatehouse_beam}, &1))

    assert Enum.any?(resources, fn
             %HostKit.Resources.Command{
               name: "gatehouse_edge_install",
               creates: "/opt/gatehouse/bin/gatehouse"
             } ->
               true

             _resource ->
               false
           end)
  end

  test "gatehouse recipe emits systemd/env/readiness resources for an existing release" do
    project =
      Code.eval_string("""
      use HostKit.DSL, providers: [HostKit.Providers.Gatehouse]

      project :edge do
        account :gatehouse, system: true, home: "/var/lib/gatehouse"

        proxy :edge, provider: :gatehouse, path: "/etc/gatehouse/config.exs" do
          service :app do
            host "app.example.com"
            target :main, url: "http://127.0.0.1:4000", active: true
          end
        end

        gatehouse :edge,
          release_path: "/opt/gatehouse",
          config_path: "/etc/gatehouse/config.exs",
          state_path: "/var/lib/gatehouse/state.etf",
          run_as: account(:gatehouse),
          cookie: "secret"
      end
      """)
      |> elem(0)

    resources = HostKit.Project.resources(project)

    assert Enum.any?(resources, &match?(%HostKit.Proxy{name: :edge, provider: :gatehouse}, &1))

    assert Enum.any?(
             resources,
             &match?(%HostKit.Resources.Account{name: "gatehouse", system: true}, &1)
           )

    assert Enum.any?(resources, &match?(%HostKit.Resources.Directory{path: "/etc/gatehouse"}, &1))

    assert Enum.any?(
             resources,
             &match?(%HostKit.Resources.EnvFile{path: "/etc/gatehouse/env"}, &1)
           )

    assert Enum.any?(resources, fn
             %HostKit.Systemd.Service{name: "gatehouse.service", service: service} ->
               Keyword.get(service, :exec_start) == "/opt/gatehouse/bin/gatehouse start" and
                 Keyword.get(service, :exec_stop) == ["/opt/gatehouse/bin/gatehouse", "stop"]

             _resource ->
               false
           end)

    assert Enum.any?(resources, fn
             %HostKit.Resources.Readiness{checks: checks} ->
               Enum.any?(
                 checks,
                 &match?(
                   %HostKit.Readiness.Systemd{
                     unit: "gatehouse.service",
                     restart: true,
                     kill: true
                   },
                   &1
                 )
               )

             _resource ->
               false
           end)
  end
end
