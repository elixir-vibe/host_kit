defmodule HostKit.Ingress.GatehouseTest do
  use ExUnit.Case, async: true

  test "Gatehouse provider renders semantic ingress as Gatehouse proxy config" do
    project =
      Code.eval_string("""
      use HostKit.DSL, providers: [HostKit.Providers.Gatehouse]

      project :demo do
        service :app do
          endpoint :http, port: 4000
        end

        service :edge do
          ingress :web, path: "/etc/gatehouse/config.exs", state: "/var/lib/gatehouse/state.etf" do
            server ":18080" do
              route host: "app.example.com" do
                proxy to: endpoint(:app, :http)
              end
            end
          end
        end
      end
      """)
      |> elem(0)

    assert {:ok, plan} = HostKit.plan(project)
    assert [%HostKit.Proxy{} = proxy] = Enum.filter(plan.resources, &match?(%HostKit.Proxy{}, &1))
    assert proxy.provider == :gatehouse
    assert proxy.path == "/etc/gatehouse/config.exs"
    assert proxy.state == "/var/lib/gatehouse/state.etf"
    assert proxy.listeners == [%{scheme: :http, opts: [port: 18_080]}]

    assert [service] = proxy.services
    assert service.hosts == ["app.example.com"]
    assert [%{url: "http://127.0.0.1:4000", active: true}] = service.targets

    rendered = HostKit.Proxy.render(proxy)
    assert rendered =~ "state(\"/var/lib/gatehouse/state.etf\")"
    assert rendered =~ "http(port: 18080)"
    assert rendered =~ "target(:main, \"http://127.0.0.1:4000\", active: true)"
  end

  test "Caddy and Gatehouse providers can both consume one ingress declaration" do
    project =
      Code.eval_string("""
      use HostKit.DSL, providers: [HostKit.Providers.Caddy, HostKit.Providers.Gatehouse]

      project :demo do
        service :app do
          endpoint :http, port: 4000
        end

        service :edge do
          ingress :web do
            server ":18080" do
              route host: "app.example.com" do
                proxy to: endpoint(:app, :http)
              end
            end
          end
        end
      end
      """)
      |> elem(0)

    assert {:ok, plan} = HostKit.plan(project)
    assert Enum.any?(plan.resources, &match?(%HostKit.Caddy.Site{}, &1))
    assert Enum.any?(plan.resources, &match?(%HostKit.Proxy{provider: :gatehouse}, &1))
  end
end
