defmodule HostKit.SystemdTargetTest do
  use ExUnit.Case, async: true

  test "resolves common target aliases" do
    assert HostKit.Systemd.Target.name(:multi_user) == "multi-user.target"
    assert HostKit.Systemd.Target.name(:network_online) == "network-online.target"
    assert HostKit.Systemd.Target.name("custom.target") == "custom.target"

    assert HostKit.Systemd.Target.names([:network_online, "postgresql.service"]) == [
             "network-online.target",
             "postgresql.service"
           ]
  end

  test "target DSL helpers write unit and install sections" do
    source = """
    use HostKit.DSL

    project :demo do
      service :web do
        daemon "web.service" do
          description "Web"
          after_target :network_online
          wants :network_online
          requires "postgresql.service"
          run exec_start: ["/usr/bin/env", "true"]
          wanted_by :multi_user
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services
    assert [%HostKit.Systemd.Service{} = unit] = service.resources
    assert unit.unit[:after] == "network-online.target"
    assert unit.unit[:wants] == "network-online.target"
    assert unit.unit[:requires] == "postgresql.service"
    assert unit.install[:wanted_by] == "multi-user.target"
  end

  test "timer targets can use timers alias" do
    source = """
    use HostKit.DSL

    project :demo do
      service :sync do
        schedule "sync.timer" do
          every :hour
          wanted_by :timers
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services
    assert [%HostKit.Systemd.Timer{} = timer] = service.resources
    assert timer.install[:wanted_by] == "timers.target"
  end
end
