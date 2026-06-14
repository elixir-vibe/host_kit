defmodule Mix.Tasks.HostKit.DownTest do
  use ExUnit.Case, async: false

  alias HostKit.{Change, Plan}
  alias HostKit.Plan.Artifact
  alias Mix.Tasks.HostKit.Down

  import ExUnit.CaptureIO

  setup do
    Mix.Task.reenable("host_kit.down")
    :ok
  end

  test "writes a down plan artifact from an up plan artifact" do
    root =
      Path.join(System.tmp_dir!(), "host-kit-down-task-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    up_path = Path.join(root, "up.plan.json")
    down_path = Path.join(root, "down.plan.json")
    before = %HostKit.Resources.File{path: "/tmp/demo", content: "old"}
    after_resource = %HostKit.Resources.File{path: "/tmp/demo", content: "new"}

    plan = %Plan{
      project: %HostKit.Project{name: :demo},
      changes: [
        %Change{
          action: :update,
          resource_id: {:file, "/tmp/demo"},
          before: before,
          after: after_resource
        }
      ]
    }

    assert :ok = Artifact.save(up_path, plan)

    output = capture_io(fn -> Down.run([up_path, "--out", down_path]) end)
    assert output =~ "1 to update"
    assert output =~ "file./tmp/demo"

    assert {:ok, down_plan} = Artifact.load(down_path)
    assert [%Change{action: :update, before: ^after_resource, after: ^before}] = down_plan.changes
  end

  test "builds a down plan from the latest tracked run" do
    root =
      Path.join(
        System.tmp_dir!(),
        "host-kit-down-last-task-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    up_path = Path.join(root, "up.plan.json")
    down_path = Path.join(root, "down.plan.json")
    runs_root = Path.join(root, "runs")
    before = %HostKit.Resources.File{path: "/tmp/demo", content: "old"}
    after_resource = %HostKit.Resources.File{path: "/tmp/demo", content: "new"}

    plan = %Plan{
      project: %HostKit.Project{name: :demo},
      changes: [
        %Change{
          action: :update,
          resource_id: {:file, "/tmp/demo"},
          before: before,
          after: after_resource
        }
      ]
    }

    assert :ok = Artifact.save(up_path, plan)

    assert {:ok, _results} =
             HostKit.apply(%Plan{plan | changes: []},
               confirm: true,
               track: true,
               hostkit_runs_root: runs_root,
               up_plan_artifact: up_path
             )

    output =
      capture_io(fn ->
        Down.run(["--last", "--runs-root", runs_root, "--out", down_path])
      end)

    assert output =~ "1 to update"
    assert {:ok, down_plan} = Artifact.load(down_path)
    assert [%Change{action: :update, before: ^after_resource, after: ^before}] = down_plan.changes
  end
end
