defmodule HostKit.Agent.SystemdTest do
  use ExUnit.Case, async: true

  test "builds a systemd service for the HostKit agent" do
    service =
      HostKit.Agent.Systemd.service(
        exec_start: [
          "/opt/host_kit/bin/host_kit",
          "agent",
          "--config",
          "/etc/host_kit/config.exs"
        ]
      )

    assert service.name == "host-kit.service"

    assert service.service[:exec_start] ==
             "/opt/host_kit/bin/host_kit agent --config /etc/host_kit/config.exs"

    assert service.service[:restart] == "on-failure"
    assert service.install[:wanted_by] == "multi-user.target"
    assert service.meta.hostkit_agent == true
    assert HostKit.Systemd.Service.validate(service) == :ok
  end
end
