defmodule HostKit.WorkspacePreviewTest do
  use ExUnit.Case, async: true

  test "preview expands to listener and Caddy site" do
    source = """
    use HostKit.DSL, providers: [HostKit.Providers.Caddy]

    project :demo do
      roots workspaces: "/var/lib/hostkit/workspaces", data: "/var/lib/hostkit/workspaces"
      prefixes user: "hk-", unit: "hk-ws-"

      workspace :blog, owner: :alice do
        service :preview do
          daemon unit_name() do
            run exec_start: ["mix", "phx.server"]
          end

          preview :http, port: 4000, domain: "alice-blog.dev.example.com"
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services
    assert service.meta.listeners.http.port == 4000

    assert [%HostKit.Systemd.Service{}, %HostKit.Caddy.Site{} = site] = service.resources
    assert site.name == :http
    assert site.host == "alice-blog.dev.example.com"

    assert [%HostKit.Caddy.Directive.ReverseProxy{upstreams: ["127.0.0.1:4000"]}] =
             site.directives

    assert [%HostKit.Monitor.Check{type: :http, target: "https://alice-blog.dev.example.com"}] =
             site.meta.monitor

    assert site.meta.telemetry.metrics == :http
    assert site.meta.logs.driver == :caddy_access
  end
end
