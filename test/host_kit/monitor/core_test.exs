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

  test "monitor structs are JSON artifact safe" do
    check = %HostKit.Monitor.Check{type: :http, name: :web}
    endpoint = %HostKit.Monitor.Endpoint{name: "web", source: check}

    assert %{"$type" => "struct", "module" => "Elixir.HostKit.Monitor.Check"} =
             HostKit.Resource.dump(check)

    assert %{"$type" => "struct", "module" => "Elixir.HostKit.Monitor.Endpoint"} =
             HostKit.Resource.dump(endpoint)
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

  test "command monitors use existing exec command shapes" do
    source = """
    use HostKit.DSL

    project :demo do
      service :ops do
        file "/usr/local/sbin/check", content: "#!/bin/sh\nexit 0\n"
        monitor :command, name: :dr_check, exec: argv("/usr/local/sbin/check", opts: [fast: true])
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [check] = HostKit.Monitor.checks(project)
    assert check.type == :command
    assert check.name == :dr_check
    assert %HostKit.CommandLine{command: "/usr/local/sbin/check", args: ["--fast"]} = check.exec
  end

  test "mix and elixir DSL helpers build command lines" do
    source = """
    use HostKit.DSL

    project :demo do
      service :ops do
        command :migrate, exec: mix("ecto.migrate", opts: [quiet: true])
        monitor :command, name: :script, exec: elixir("script.exs", opts: [name: "demo"])
        monitor :command, name: :eval, exec: eval("IO.puts(:ok)")
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services
    assert [%HostKit.Resources.Command{} = command] = service.resources
    assert command.exec == {"/usr/local/bin/mix", ["ecto.migrate", "--quiet"]}
    assert [script, eval] = HostKit.Monitor.checks(project)

    assert %HostKit.CommandLine{
             command: "/usr/local/bin/elixir",
             args: ["script.exs", "--name", "demo"]
           } =
             script.exec

    assert %HostKit.CommandLine{command: "/usr/local/bin/elixir", args: ["-e", "IO.puts(:ok)"]} =
             eval.exec
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
