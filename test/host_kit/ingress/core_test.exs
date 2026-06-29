defmodule HostKit.IngressTest do
  use ExUnit.Case, async: true

  test "ingress DSL validates options through DSLCore option schemas" do
    assert_raise ArgumentError, ~r/unknown option :bad for ingress_opts at nofile:4/, fn ->
      Code.eval_string("""
      use HostKit.DSL

      project :demo do
        ingress :web, bad: true do
        end
      end
      """)
    end

    assert_raise ArgumentError, ~r/unknown option :bad for server_opts at nofile:5/, fn ->
      Code.eval_string("""
      use HostKit.DSL

      project :demo do
        ingress :web do
          server ":443", bad: true do
          end
        end
      end
      """)
    end

    assert_raise ArgumentError, ~r/unknown option :bad for route_opts at nofile:6/, fn ->
      Code.eval_string("""
      use HostKit.DSL

      project :demo do
        ingress :web do
          server ":443" do
            route host: "app.example.com", bad: true do
            end
          end
        end
      end
      """)
    end

    assert_raise ArgumentError, ~r/unknown option :bad for proxy_opts at nofile:7/, fn ->
      Code.eval_string("""
      use HostKit.DSL

      project :demo do
        ingress :web do
          server ":443" do
            route host: "app.example.com" do
              proxy to: "http://127.0.0.1:4000", bad: true
            end
          end
        end
      end
      """)
    end
  end

  test "ingress DSL compiles to structs and Caddy sites" do
    project =
      Code.eval_string("""
      use HostKit.DSL, providers: [HostKit.Providers.Caddy]

      project :demo do
        service :app do
          endpoint :http, port: 4000
        end

        service :edge do
          ingress :web do
            server ":443" do
              tls :auto

              route host: "app.example.com" do
                proxy to: endpoint(:app, :http)
              end
            end
          end
        end
      end
      """)
      |> elem(0)

    assert [%HostKit.Ingress{name: :web}] =
             project
             |> HostKit.Project.resources()
             |> Enum.filter(&match?(%HostKit.Ingress{}, &1))

    assert {:ok, plan} = HostKit.plan(project)

    assert [%HostKit.Caddy.Site{host: "app.example.com", directives: [directive]}] =
             Enum.filter(plan.resources, &match?(%HostKit.Caddy.Site{}, &1))

    assert %HostKit.Caddy.Directive.ReverseProxy{upstreams: ["127.0.0.1:4000"]} = directive
  end
end
