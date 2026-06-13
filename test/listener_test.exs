defmodule HostKit.ListenerTest do
  use ExUnit.Case, async: true

  test "named listeners are stored on the service and systemd unit" do
    source = """
    use HostKit.DSL

    project :demo do
      service :web do
        daemon "web.service" do
          run exec_start: ["/usr/bin/env", "true"]
          listen :http, port: 3000, on: :loopback
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services
    assert %HostKit.Listener{port: 3000, on: {127, 0, 0, 1}} = service.meta.listeners.http
    assert [%HostKit.Systemd.Service{} = unit] = service.resources
    assert unit.meta.listen == [%{port: 3000, on: {127, 0, 0, 1}}]
  end

  test "caddy reverse proxy can consume named listeners" do
    source = """
    use HostKit.DSL, providers: [HostKit.Providers.Caddy]

    project :demo do
      service :web do
        daemon "web.service" do
          run exec_start: ["/usr/bin/env", "true"]
          listen :http, port: 3000, on: :loopback
        end

        caddy_site :web, "web.example.com" do
          reverse_proxy listener(:http)
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [_unit, site] = HostKit.Project.resources(project)

    assert [%HostKit.Caddy.Directive.ReverseProxy{upstreams: ["127.0.0.1:3000"]}] =
             site.directives
  end

  test "anonymous listeners still attach to the active systemd unit" do
    source = """
    use HostKit.DSL

    project :demo do
      service :web do
        daemon "web.service" do
          run exec_start: ["/usr/bin/env", "true"]
          listen 3000, on: {127, 0, 0, 1}
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [%HostKit.Systemd.Service{} = unit] = HostKit.Project.resources(project)
    assert unit.meta.listen == [%{port: 3000, on: {127, 0, 0, 1}}]
  end
end
