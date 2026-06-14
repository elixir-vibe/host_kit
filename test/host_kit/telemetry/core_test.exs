defmodule HostKit.TelemetryTest do
  use ExUnit.Case, async: true

  test "project observability telemetry defaults apply to resources" do
    source = """
    use HostKit.DSL, providers: [HostKit.Providers.Caddy]

    project :demo do
      observability do
        telemetry logs: true, metrics: true, traces: false, attributes: [environment: :test]
      end

      service :web do
        daemon do
          exec ["/usr/bin/env", "true"]
          listen :http, port: 4000
        end

        caddy_site "web.example.com" do
          reverse_proxy :http
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [systemd, caddy] = HostKit.Telemetry.signals(project)

    assert systemd.resource_id == {:systemd_service, "web.service"}
    assert systemd.signals == [:logs, :metrics]
    assert systemd.attributes == %{environment: :test}

    assert to_string(caddy.resource_id) == "caddy_site.web.example.com"
    assert caddy.signals == [:logs, :metrics]
    assert caddy.attributes == %{environment: :test}
  end

  test "service defaults merge over project defaults" do
    source = """
    use HostKit.DSL

    project :demo do
      observability do
        telemetry logs: true, metrics: true, attributes: [environment: :prod]
      end

      service :worker do
        observability do
          telemetry metrics: false, attributes: [component: :worker]
        end

        daemon do
          exec ["/usr/bin/env", "true"]
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [signal] = HostKit.Telemetry.signals(project)
    assert signal.signals == [:logs]
    assert signal.attributes == %{environment: :prod, component: :worker}
  end

  test "resource telemetry overrides inherited defaults" do
    source = """
    use HostKit.DSL

    project :demo do
      observability do
        telemetry logs: true, metrics: true
      end

      service :worker do
        daemon do
          exec ["/usr/bin/env", "true"]
          telemetry logs: :journald, metrics: false, service_name: "worker"
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [signal] = HostKit.Telemetry.signals(project)
    assert signal.service_name == "worker"
    assert signal.logs == :journald
    assert signal.metrics == false
    assert signal.signals == [:logs]
  end

  test "systemd and caddy resources get default telemetry when no global defaults exist" do
    source = """
    use HostKit.DSL, providers: [HostKit.Providers.Caddy]

    project :demo do
      service :web do
        daemon do
          exec ["/usr/bin/env", "true"]
          listen :http, port: 4000
        end

        caddy_site "web.example.com" do
          reverse_proxy :http
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [systemd, caddy] = HostKit.Telemetry.signals(project)
    assert systemd.logs == :journald
    assert systemd.metrics == :systemd
    assert caddy.logs == :access
    assert caddy.metrics == :http
  end
end
