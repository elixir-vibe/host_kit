defmodule HostKit.LogsTest do
  use ExUnit.Case, async: true

  test "project observability log defaults apply to resources" do
    source = """
    use HostKit.DSL, providers: [HostKit.Providers.Caddy]

    project :demo, providers: [HostKit.Providers.Caddy] do
      observability do
        logs driver: :journald, retention: "14d", ship: true, attributes: [environment: :test]
      end

      service :web do
        daemon "web.service" do
          run exec_start: ["/usr/bin/env", "true"]
        end

        caddy_site :web, "web.example.com" do
          reverse_proxy "127.0.0.1:4000"
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [systemd, caddy] = HostKit.Logs.configs(project)

    assert systemd.resource_id == {:systemd_service, "web.service"}
    assert systemd.driver == :journald
    assert systemd.retention == "14d"
    assert systemd.ship == true
    assert systemd.attributes == %{environment: :test}

    assert to_string(caddy.resource_id) == "caddy_site.web"
    assert caddy.driver == :journald
  end

  test "service defaults merge over project defaults" do
    source = """
    use HostKit.DSL

    project :demo do
      observability do
        logs driver: :journald, ship: true, attributes: [environment: :prod]
      end

      service :worker do
        observability do
          logs retention: "30d", attributes: [component: :worker]
        end

        daemon "worker.service" do
          run exec_start: ["/usr/bin/env", "true"]
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [config] = HostKit.Logs.configs(project)
    assert config.driver == :journald
    assert config.retention == "30d"
    assert config.attributes == %{environment: :prod, component: :worker}
  end

  test "systemd logs attach metadata and service directives" do
    source = """
    use HostKit.DSL

    project :demo do
      service :web do
        daemon "web.service" do
          run exec_start: ["/usr/bin/env", "true"]
          logs identifier: "web", stdout: :journal, stderr: :journal, ship: true
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [%HostKit.Systemd.Service{} = service] = HostKit.Project.resources(project)
    assert service.service[:standard_output] == :journal
    assert service.service[:standard_error] == :journal
    assert service.service[:syslog_identifier] == "web"

    assert [config] = HostKit.Logs.configs(project)
    assert config.identifier == "web"
    assert config.ship == true
  end
end
