defmodule HostKit.SystemdAliasesTest do
  use ExUnit.Case, async: true

  test "daemon aliases persistent service units" do
    source = """
    use HostKit.DSL

    project :demo do
      prefixes unit: "demo-", user: "demo-"

      service :web do
        daemon unit_name() do
          unit description: "Web daemon"
          run user: service_user(), exec_start: ["/usr/bin/env", "true"], restart: :on_failure
          install wanted_by: "multi-user.target"
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services
    assert [%HostKit.Systemd.Service{} = unit] = service.resources
    assert unit.name == "demo-web.service"
    assert unit.unit[:description] == "Web daemon"
    assert unit.service[:user] == "demo-web"
    assert unit.service[:restart] == "on-failure"
  end

  test "daemon and schedule normalize unit names" do
    source = """
    use HostKit.DSL

    project :prod do
      prefixes unit: "toys-"

      service :health_alert do
        daemon :health_alert do
          exec ["/usr/bin/env", "true"]
        end

        schedule :health_alert do
          every "1h"
        end

        daemon "custom" do
          exec ["/usr/bin/env", "true"]
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Systemd.Service{name: "toys-health-alert.service"}, &1)
           )

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Systemd.Timer{name: "toys-health-alert.timer"}, &1)
           )

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Systemd.Service{name: "custom.service"}, &1)
           )
  end

  test "exec accepts built argv command lines" do
    source = """
    use HostKit.DSL

    project :prod do
      service :search do
        daemon do
          exec argv("mix", args: ["exograph.web"], opts: [backend: "duckdb", port: 4200])
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    [service] = project.services
    [%HostKit.Systemd.Service{} = unit] = service.resources

    assert unit.service[:exec_start] == "mix exograph.web --backend duckdb --port 4200"
  end

  test "job and schedule alias service and timer units" do
    source = """
    use HostKit.DSL

    project :demo do
      prefixes unit: "demo-"

      service :sync do
        job unit_name("-sync.service") do
          run type: :oneshot, exec_start: ["/usr/bin/env", "true"]
        end

        schedule unit_name("-sync.timer") do
          timer on_calendar: "hourly", persistent: true
          install wanted_by: "timers.target"
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services

    assert [
             %HostKit.Systemd.Service{name: "demo-sync-sync.service"},
             %HostKit.Systemd.Timer{name: "demo-sync-sync.timer"}
           ] = service.resources
  end
end
