defmodule HostKit.ProxyTest do
  use ExUnit.Case, async: true

  test "renders Gatehouse config from quoted AST" do
    proxy = %HostKit.Proxy{
      name: :edge,
      provider: :gatehouse,
      services: [
        %{
          name: :app,
          hosts: ["app.example.com"],
          targets: [
            %{name: :main, safe_rpc: [socket: "/run/app.sock"], active: true}
          ]
        }
      ]
    }

    expected =
      "import Gatehouse.Config\nservice(:app) do\n  host(\"app.example.com\")\n  target(:main, safe_rpc: [socket: \"/run/app.sock\"], active: true)\nend"

    assert HostKit.Proxy.render(proxy) == expected
  end

  test "renders endpoint targets" do
    proxy = %HostKit.Proxy{
      name: :edge,
      provider: :gatehouse,
      services: [
        %{
          name: :app,
          hosts: ["app.example.com"],
          targets: [
            %{name: :main, to: HostKit.Endpoint.new(:hello_phoenix, :http), active: true}
          ]
        }
      ]
    }

    assert HostKit.Proxy.render(proxy) ==
             "import Gatehouse.Config\nservice(:app) do\n  host(\"app.example.com\")\n  target(:main, endpoint(:hello_phoenix, :http), active: true)\nend"
  end

  test "builds proxy resources from generic DSL" do
    project =
      Code.eval_string("""
      use HostKit.DSL

      project :demo do
        proxy :edge, provider: :gatehouse do
          service :app do
            host "app.example.com"
            target :main, safe_rpc: [socket: "/run/app.sock"], active: true
          end
        end
      end
      """)
      |> elem(0)

    assert [%HostKit.Proxy{name: :edge, provider: :gatehouse} = proxy] = project.proxies
    assert [proxy] == HostKit.Project.resources(project)
    assert [service] = proxy.services
    assert service.name == :app
    assert service.hosts == ["app.example.com"]
    assert [%{name: :main, safe_rpc: [socket: "/run/app.sock"], active: true}] = service.targets
  end

  test "plan resolves endpoint targets from service declarations" do
    project =
      Code.eval_string("""
      use HostKit.DSL

      project :demo do
        service :hello_phoenix do
          endpoint :http, port: 4000, protocol: :http, health: "/health"
        end

        proxy :edge, provider: :gatehouse do
          service :app do
            host "app.example.com"
            target :main, to: endpoint(:hello_phoenix, :http), active: true
          end
        end
      end
      """)
      |> elem(0)

    assert {:ok, plan} = HostKit.plan(project)
    proxy = Enum.find(plan.resources, &match?(%HostKit.Proxy{}, &1))
    assert [service] = proxy.services
    assert [%{to: %HostKit.Endpoint{host: "127.0.0.1", port: 4000}}] = service.targets

    assert HostKit.Proxy.render(proxy) =~
             "target(:main, \"http://127.0.0.1:4000\", active: true)"
  end

  test "builds endpoint targets from generic DSL" do
    project =
      Code.eval_string("""
      use HostKit.DSL

      project :demo do
        proxy :edge, provider: :gatehouse do
          service :app do
            host "app.example.com"
            target :main, to: endpoint(:hello_phoenix, :http), active: true
          end
        end
      end
      """)
      |> elem(0)

    assert [%HostKit.Proxy{} = proxy] = project.proxies
    assert [service] = proxy.services

    assert [%{name: :main, to: %HostKit.Endpoint{service: :hello_phoenix, name: :http}}] =
             service.targets
  end
end
