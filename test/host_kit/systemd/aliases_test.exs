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
