defmodule HostKit.MonitorTest do
  use ExUnit.Case, async: true

  test "collects monitor checks from resources" do
    source = """
    use HostKit.DSL, providers: [HostKit.Providers.Caddy]

    project :demo do
      service :web do
        daemon "web.service" do
          run exec_start: ["/usr/bin/env", "true"]
          monitor :systemd, name: :web_unit, expect: [state: :active], severity: :critical
        end

        caddy_site :web, "web.example.com" do
          reverse_proxy "127.0.0.1:4000"
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
    assert to_string(http.resource_id) == "caddy_site.web"
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
