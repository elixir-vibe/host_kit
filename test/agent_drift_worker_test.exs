defmodule HostKit.Agent.DriftWorkerTest do
  use ExUnit.Case, async: false

  setup do
    HostKit.Agent.reset()
    :ok
  end

  test "run_once records not configured error" do
    assert {:error, :agent_not_configured} = HostKit.Agent.run_plan()
    assert %{last_plan: {:error, :agent_not_configured}} = HostKit.Agent.status()
  end

  test "run_once builds and records a plan for configured project" do
    resource = HostKit.Resources.Directory.new("/tmp/example")
    service = HostKit.Service.new(:demo, resources: [resource])
    project = HostKit.Project.new(:demo) |> HostKit.Project.add_service(service)

    assert :ok = HostKit.Agent.configure(project: project, target: HostKit.Target.local(:dev))

    assert {:ok, %HostKit.Plan{} = plan} = HostKit.Agent.run_plan()
    assert plan.summary == %{directory: 1}

    status = HostKit.Agent.status()
    assert {:ok, %HostKit.Plan{summary: %{directory: 1}}} = status.last_plan
    assert [%{event: {:plan_completed, %{directory: 1}}} | _] = status.events
  end

  test "interval parser accepts duration suffixes" do
    assert {:ok, pid} = HostKit.Agent.DriftWorker.start_link(every: "1h", name: nil)
    assert Process.alive?(pid)
    GenServer.stop(pid)
  end
end
