defmodule HostKit.MonitorTest do
  use ExUnit.Case, async: true

  test "collects monitor checks from resources" do
    source = """
    use HostKit.DSL, providers: [HostKit.Providers.Caddy]

    project :demo do
      service :web do
        daemon do
          exec ["/usr/bin/env", "true"]
          listen :http, port: 4000
          monitor :systemd, name: :web_unit, expect: [state: :active], severity: :critical
        end

        caddy_site "web.example.com" do
          reverse_proxy :http
          monitor :http, name: :web_http, url: "https://web.example.com", expect: [status: 200]
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    checks = HostKit.Monitor.checks(project)

    assert [systemd, http] = checks
    assert systemd.type == :systemd
    assert systemd.name == :web_unit
    assert systemd.expect == [state: :active]
    assert systemd.severity == :critical
    assert systemd.resource_id == {:systemd_service, "web.service"}

    assert http.type == :http
    assert http.name == :web_http
    assert http.target == "https://web.example.com"
    assert http.expect == [status: 200]
    assert to_string(http.resource_id) == "caddy_site.web.example.com"
  end

  test "projects http monitors into provider-neutral endpoint checks" do
    source = """
    use HostKit.DSL, providers: [HostKit.Providers.Caddy]

    project :demo do
      service :web do
        caddy_site "web.example.com" do
          reverse_proxy "127.0.0.1:4000"

          monitor :http,
            name: "web",
            group: "demo",
            url: "https://web.example.com/health",
            interval: "1m",
            expect: [status: 200, response_time_lt: 5000],
            alerts: [:telegram],
            severity: :critical
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)

    assert [endpoint] = HostKit.Monitor.endpoint_checks(project)
    assert endpoint.name == "web"
    assert endpoint.group == "demo"
    assert endpoint.url == "https://web.example.com/health"
    assert endpoint.interval == "1m"
    assert endpoint.expect == [status: 200, response_time_lt: 5000]
    assert endpoint.alerts == [:telegram]
    assert endpoint.severity == :critical
    assert %HostKit.Monitor.Check{type: :http} = endpoint.source
  end

  test "monitor after a resource attaches to the last resource" do
    source = """
    use HostKit.DSL

    project :demo do
      service :web do
        directory "/srv/app", mode: :private_dir
        monitor :filesystem, name: :app_dir, expect: [exists: true]
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [check] = HostKit.Monitor.checks(project)
    assert check.type == :filesystem
    assert check.resource_id == {:directory, "/srv/app"}
  end
end
