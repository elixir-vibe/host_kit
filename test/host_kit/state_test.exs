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
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600

    File.rm!(path)
  end

  test "keeps unknown JSON keys as strings" do
    path =
      Path.join(System.tmp_dir!(), "host-kit-state-#{System.unique_integer([:positive])}.json")

    unknown = "hostkit_unknown_#{System.unique_integer([:positive])}"
    File.write!(path, Jason.encode!(%{"version" => 1, "data" => %{unknown => true}}))
    on_exit(fn -> File.rm(path) end)

    assert {:ok, %{version: 1, data: data}} = HostKit.State.read(path)
    assert data[unknown] == true
  end

  test "creates snapshots from agent status" do
    status = %{started_at: DateTime.utc_now(), events: [], project: :demo}

    snapshot = HostKit.State.snapshot(status)

    assert snapshot.kind == :agent_status
    assert snapshot.name == :demo
    assert snapshot.data == status
  end
end
