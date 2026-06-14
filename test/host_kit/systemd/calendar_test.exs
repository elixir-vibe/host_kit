defmodule HostKit.SystemdCalendarTest do
  use ExUnit.Case, async: true

  test "resolves common calendar aliases" do
    assert HostKit.Systemd.Calendar.name(:hour) == "hourly"
    assert HostKit.Systemd.Calendar.name(:daily) == "daily"
    assert HostKit.Systemd.Calendar.name("Mon *-*-* 02:00:00") == "Mon *-*-* 02:00:00"
  end

  test "timer DSL accepts atom calendar values" do
    source = """
    use HostKit.DSL

    project :demo do
      service :sync do
        schedule "sync.timer" do
          timer on_calendar: :hourly, persistent: true
          wanted_by :timers
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services
    assert [%HostKit.Systemd.Timer{} = timer] = service.resources
    assert timer.timer[:on_calendar] == "hourly"
    assert timer.timer[:persistent] == true
  end

  test "semantic timer helpers write timer options" do
    source = """
    use HostKit.DSL

    project :demo do
      service :sync do
        schedule "sync.timer" do
          every :hour
          persistent true
          on_boot "10min"
          wanted_by :timers
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services
    assert [%HostKit.Systemd.Timer{} = timer] = service.resources
    assert timer.timer[:on_calendar] == "hourly"
    assert timer.timer[:persistent] == true
    assert timer.timer[:on_boot_sec] == "10min"
  end
end
