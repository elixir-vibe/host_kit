defmodule HostKit.Integration.GatehouseConfigTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @tag timeout: 300_000
  test "HostKit Gatehouse proxy config is accepted by the real Gatehouse parser" do
    if File.dir?(gatehouse_path()) do
      proxy = %HostKit.Proxy{
        name: :edge,
        provider: :gatehouse,
        state: "/var/lib/gatehouse/state.etf",
        listeners: [%{scheme: :http, opts: [port: 18_080]}],
        services: [
          %{
            name: :app,
            hosts: ["app.example.com"],
            targets: [
              %{name: :main, url: "http://127.0.0.1:4000", active: true},
              %{name: :rpc, safe_rpc: [socket: "/run/app.sock"], metadata: %{role: "rpc"}}
            ]
          }
        ]
      }

      assert_gatehouse_accepts!(HostKit.Proxy.render(proxy), "static")
    else
      IO.puts("Skipping Gatehouse parser integration: #{gatehouse_path()} does not exist")
    end
  end

  @tag timeout: 300_000
  test "resolved endpoint proxy targets render as real Gatehouse URL targets" do
    if File.dir?(gatehouse_path()) do
      project =
        Code.eval_string("""
        use HostKit.DSL

        project :demo do
          service :hello_phoenix do
            endpoint :http, port: 4000, protocol: :http, health: "/health"
          end

          proxy :edge, provider: :gatehouse do
            state "/var/lib/gatehouse/state.etf"
            http port: 18_080

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

      assert_gatehouse_accepts!(HostKit.Proxy.render(proxy), "endpoint")
    else
      IO.puts("Skipping Gatehouse parser integration: #{gatehouse_path()} does not exist")
    end
  end

  defp assert_gatehouse_accepts!(source, label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "hostkit-gatehouse-#{label}-#{System.unique_integer([:positive])}.exs"
      )

    File.write!(path, source)

    code = """
    config = Gatehouse.Config.read!(#{inspect(path)})
    [service] = config.services
    true = service.hosts == ["app.example.com"]
    true = Enum.any?(service.targets, &(&1.name == "main" and &1.active?))
    IO.puts("ok")
    """

    try do
      {output, status} =
        System.cmd("mix", ["run", "-e", code],
          cd: gatehouse_path(),
          env: [{"MIX_ENV", "test"}],
          stderr_to_stdout: true
        )

      assert status == 0, output
      assert "ok" in String.split(output, "\n", trim: true)
    after
      File.rm(path)
    end
  end

  defp gatehouse_path do
    Path.expand("../../../gatehouse", __DIR__)
  end
end
