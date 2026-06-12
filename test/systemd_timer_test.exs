defmodule HostKit.SystemdTimerTest do
  use ExUnit.Case, async: true

  test "renders systemd timer from keyword section DSL" do
    project = HostKit.load!(fixture_path("timer_project.hostkit"))

    assert {:ok, rendered} =
             HostKit.Render.render(project, {:systemd_timer, "toys-hex-mirror-sync.timer"})

    assert IO.iodata_to_binary(rendered) == """
           [Unit]
           Description=Run Hex mirror sync hourly
           [Timer]
           OnBootSec=10min
           OnUnitActiveSec=1h
           Persistent=true
           RandomizedDelaySec=10min
           [Install]
           WantedBy=timers.target
           """
  end

  defp fixture_path(name), do: Path.expand("fixtures/#{name}", __DIR__)
end
