defmodule HostKit.AgentTest do
  use ExUnit.Case, async: false

  test "application starts HostKit supervision tree" do
    assert Process.whereis(HostKit.Supervisor)
    assert Process.whereis(HostKit.Agent.State)
  end

  test "agent exposes runtime status" do
    status = HostKit.Agent.status()

    assert %DateTime{} = status.started_at
    assert is_boolean(status.configured?)
    assert is_list(status.events)
  end

  test "agent can be configured with project and target" do
    project = HostKit.Project.new(:demo)
    target = HostKit.Target.local(:dev)

    assert :ok = HostKit.Agent.configure(project: project, target: target)

    status = HostKit.Agent.status()
    assert status.configured? == true
    assert status.project == :demo
    assert status.target == :dev
    assert [%{event: :configured} | _] = status.events
  end
end
