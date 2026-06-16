defmodule HostKit.SystemdCalendarTest do
  use ExUnit.Case, async: true

  test "resolves common calendar aliases" do
    assert HostKit.Systemd.Calendar.name(:hour) == "hourly"
    assert HostKit.Systemd.Calendar.name(:daily) == "daily"
    assert HostKit.Systemd.Calendar.name("Mon *-*-* 02:00:00") == "Mon *-*-* 02:00:00"
  end

  test "builds typed calendar expressions" do
    assert HostKit.Systemd.Calendar.daily_at(~T[02:30:00]) == "*-*-* 02:30:00"
    assert HostKit.Systemd.Calendar.weekly_at(:monday, "02:30") == "Mon *-*-* 02:30:00"
    assert HostKit.Systemd.Calendar.monthly_at(1, "02:30") == "*-*-01 02:30:00"
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

  test "typed schedule helpers write timer options" do
    source = """
    use HostKit.DSL

    project :demo do
      service :sync do
        schedule "sync.timer" do
          daily at: ~T[02:30:00]
          jitter "15m"
          repeat_after "1h"
          after_boot "10min"
          wanted_by :timers
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services
    assert [%HostKit.Systemd.Timer{} = timer] = service.resources
    assert timer.timer[:on_calendar] == "*-*-* 02:30:00"
    assert timer.timer[:randomized_delay_sec] == "15m"
    assert timer.timer[:on_unit_active_sec] == "1h"
    assert timer.timer[:on_boot_sec] == "10min"
  end

  test "weekly and monthly schedule helpers write timer options" do
    source = """
    use HostKit.DSL

    project :demo do
      service :weekly do
        schedule "weekly.timer" do
          weekly :monday, at: "03:00"
        end
      end

      service :monthly do
        schedule "monthly.timer" do
          monthly day: 1, at: "04:00"
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [weekly, monthly] = project.services
    assert [%HostKit.Systemd.Timer{} = weekly_timer] = weekly.resources
    assert [%HostKit.Systemd.Timer{} = monthly_timer] = monthly.resources
    assert weekly_timer.timer[:on_calendar] == "Mon *-*-* 03:00:00"
    assert monthly_timer.timer[:on_calendar] == "*-*-01 04:00:00"
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
