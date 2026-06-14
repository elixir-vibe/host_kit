defmodule HostKit.RunRecordTest do
  use ExUnit.Case, async: true

  alias HostKit.{Change, Plan}

  test "tracked apply writes minimal run record under configurable runs root" do
    root = Path.join(System.tmp_dir!(), "hostkit-runs-#{System.unique_integer([:positive])}")
    path = Path.join(root, "demo.txt")
    runs_root = Path.join(root, "runs")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    file = %HostKit.Resources.File{path: path, content: "hello", mode: 0o644}

    plan = %Plan{
      project: %HostKit.Project{name: :tracked},
      changes: [%Change{action: :create, resource_id: {:file, path}, after: file}]
    }

    assert {:ok, _results} =
             HostKit.apply(plan, confirm: true, track: true, hostkit_runs_root: runs_root)

    assert [record_path] = Path.wildcard(Path.join(runs_root, "*.json"))
    assert {:ok, record} = record_path |> File.read!() |> Jason.decode()
    assert record["project"] == "tracked"
    assert record["direction"] == "up"
    assert [%{"action" => "create", "status" => "applied"}] = record["changes"]
  end
end
