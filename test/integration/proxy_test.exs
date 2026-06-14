defmodule HostKit.ProxyIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  test "applies Gatehouse proxy config to a temp path" do
    path =
      Path.join(System.tmp_dir!(), "hostkit-gatehouse-#{System.unique_integer([:positive])}.exs")

    project =
      Code.eval_string("""
      use HostKit.DSL

      project :demo do
        proxy :edge, provider: :gatehouse, path: #{inspect(path)} do
          service :app do
            host "app.example.com"
            target :main, safe_rpc: [socket: "/tmp/app.sock"], active: true
          end
        end
      end
      """)
      |> elem(0)

    {:ok, plan} = HostKit.Plan.build(project)
    assert {:ok, _results} = HostKit.Apply.run(plan, confirm: true)
    assert File.exists?(path)

    assert File.read!(path) =~
             "target(:main, safe_rpc: [socket: \"/tmp/app.sock\"], active: true)"
  end
end
