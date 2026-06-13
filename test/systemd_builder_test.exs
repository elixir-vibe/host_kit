defmodule HostKit.SystemdBuilderTest do
  use ExUnit.Case, async: true

  test "service builder shares DSL directive coercion" do
    service =
      HostKit.Systemd.Service.new("demo.service",
        unit: [after: :network_online, wants: [:network_online]],
        service: [exec_start: ["/usr/bin/env", "true"], restart: :on_failure],
        install: [wanted_by: :multi_user]
      )

    assert service.unit[:after] == "network-online.target"
    assert service.unit[:wants] == ["network-online.target"]
    assert service.service[:exec_start] == "/usr/bin/env true"
    assert service.service[:restart] == "on-failure"
    assert service.install[:wanted_by] == "multi-user.target"
  end

  test "timer builder shares DSL directive coercion" do
    timer =
      HostKit.Systemd.Timer.new("demo.timer",
        timer: [on_calendar: :hourly, persistent: true],
        install: [wanted_by: :timers]
      )

    assert timer.timer[:on_calendar] == "hourly"
    assert timer.install[:wanted_by] == "timers.target"
  end
end
