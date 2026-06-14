defmodule HostKit.EndpointTest do
  use ExUnit.Case, async: true

  test "validates endpoint declarations" do
    assert %HostKit.Endpoint{name: :http, protocol: :http, host: "127.0.0.1", port: 4000} =
             HostKit.Endpoint.declaration(:http, port: 4000)

    assert_raise ArgumentError, ~r/port must be an integer from 1 to 65535/, fn ->
      HostKit.Endpoint.declaration(:http, port: 0)
    end

    assert_raise ArgumentError, ~r/protocol must be :http or :https/, fn ->
      HostKit.Endpoint.declaration(:http, port: 4000, protocol: :tcp)
    end
  end

  test "validates endpoint references" do
    assert %HostKit.Endpoint{service: :app, name: :http} = HostKit.Endpoint.new(:app, :http)

    assert_raise ArgumentError, ~r/service name must be an atom or string/, fn ->
      HostKit.Endpoint.new({:bad, :service}, :http)
    end
  end

  test "unresolved endpoint diagnostics include suggestions" do
    project =
      Code.eval_string("""
      use HostKit.DSL, providers: [HostKit.Providers.Caddy]

      project :demo do
        service :app do
          endpoint :web, port: 4000
        end

        service :edge do
          caddy_site :edge, ":8080" do
            reverse_proxy endpoint(:app, :http)
          end
        end
      end
      """)
      |> elem(0)

    assert {:error, diagnostics} = HostKit.plan(project)
    assert [diagnostic] = diagnostics.errors
    assert diagnostic.code == :endpoint_unresolved
    assert diagnostic.message == "unknown endpoint :app.:http"
    assert diagnostic.hint == "did you mean :app.:web?"
    assert diagnostic.line
  end
end
