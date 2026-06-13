defmodule HostKit.ProxyTest do
  use ExUnit.Case, async: true

  test "renders xamal_proxy config from quoted AST" do
    proxy = %HostKit.Proxy{
      name: :edge,
      provider: :xamal_proxy,
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
      "import XamalProxy.Config\nservice(:app) do\n  host(\"app.example.com\")\n  target(:main, safe_rpc: [socket: \"/run/app.sock\"], active: true)\nend"

    assert HostKit.Proxy.render(proxy) == expected
  end

  test "builds proxy resources from generic DSL" do
    project =
      Code.eval_string("""
      use HostKit.DSL

      project :demo do
        proxy :edge, provider: :xamal_proxy do
          service :app do
            host "app.example.com"
            target :main, safe_rpc: [socket: "/run/app.sock"], active: true
          end
        end
      end
      """)
      |> elem(0)

    assert [%HostKit.Proxy{name: :edge, provider: :xamal_proxy} = proxy] = project.proxies
    assert [proxy] == HostKit.Project.resources(project)
    assert [service] = proxy.services
    assert service.name == :app
    assert service.hosts == ["app.example.com"]
    assert [%{name: :main, safe_rpc: [socket: "/run/app.sock"], active: true}] = service.targets
  end
end
