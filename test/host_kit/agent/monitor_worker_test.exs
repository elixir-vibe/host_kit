defmodule HostKit.Agent.MonitorWorkerTest do
  use ExUnit.Case, async: false

  setup do
    HostKit.Agent.reset()
    :ok
  end

  test "run_once records not configured error" do
    assert {:error, :agent_not_configured} = HostKit.Agent.run_monitor()
    assert %{last_monitor: {:error, :agent_not_configured}} = HostKit.Agent.status()
  end

  test "run_once executes configured project monitors and records summary" do
    path =
      Path.join(System.tmp_dir!(), "host-kit-agent-monitor-#{System.unique_integer([:positive])}")

    File.write!(path, "ok")

    project = project_with_check(HostKit.Monitor.check(:filesystem, target: path))
    assert :ok = HostKit.Agent.configure(project: project, target: HostKit.Target.local(:dev))

    assert {:ok, [result]} = HostKit.Agent.run_monitor()
    assert result.status == :ok

    status = HostKit.Agent.status()
    assert {:ok, [%HostKit.Monitor.Result{status: :ok}]} = status.last_monitor
    assert [%{event: {:monitor_completed, %{ok: 1, error: 0}}} | _] = status.events

    File.rm!(path)
  end

  test "interval parser accepts duration suffixes" do
    assert {:ok, pid} = HostKit.Agent.MonitorWorker.start_link(every: "1h", name: nil)
    assert Process.alive?(pid)
    GenServer.stop(pid)
  end

  defp project_with_check(check) do
    resource = HostKit.Resources.Directory.new("/tmp/example", meta: %{monitor: [check]})
    service = HostKit.Service.new(:demo, resources: [resource])
    HostKit.Project.new(:demo) |> HostKit.Project.add_service(service)
  end
end
