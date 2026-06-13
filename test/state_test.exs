defmodule HostKit.StateTest do
  use ExUnit.Case, async: true

  test "writes and reads plan snapshots" do
    path =
      Path.join(System.tmp_dir!(), "host-kit-state-#{System.unique_integer([:positive])}.json")

    project = HostKit.Project.new(:demo)
    plan = %HostKit.Plan{project: project, summary: %{directory: 1}}

    assert :ok = HostKit.State.write(plan, path, meta: %{target: :dev})
    assert {:ok, snapshot} = HostKit.State.read(path)

    assert snapshot.version == 1
    assert snapshot.kind == "plan"
    assert snapshot.name == "demo"
    assert snapshot.meta.target == "dev"
    assert snapshot.data.summary.directory == 1

    File.rm!(path)
  end

  test "creates snapshots from agent status" do
    status = %{started_at: DateTime.utc_now(), events: [], project: :demo}

    snapshot = HostKit.State.snapshot(status)

    assert snapshot.kind == :agent_status
    assert snapshot.name == :demo
    assert snapshot.data == status
  end
end
