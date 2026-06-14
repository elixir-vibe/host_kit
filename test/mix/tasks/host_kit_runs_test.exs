defmodule Mix.Tasks.HostKit.RunsTest do
  use ExUnit.Case, async: false

  alias HostKit.{Change, Plan}
  alias Mix.Tasks.HostKit.Runs

  import ExUnit.CaptureIO

  setup do
    Mix.Task.reenable("host_kit.runs")
    :ok
  end

  test "lists tracked runs from a runs root" do
    root =
      Path.join(System.tmp_dir!(), "host-kit-runs-task-#{System.unique_integer([:positive])}")

    file_path = Path.join(root, "demo.txt")
    runs_root = Path.join(root, "runs")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    plan = %Plan{
      project: %HostKit.Project{name: :runs_task},
      changes: [
        %Change{
          action: :create,
          resource_id: {:file, file_path},
          after: %HostKit.Resources.File{path: file_path, content: "hello"}
        }
      ]
    }

    assert {:ok, _results} =
             HostKit.apply(plan, confirm: true, track: true, hostkit_runs_root: runs_root)

    output = capture_io(fn -> Runs.run(["--runs-root", runs_root]) end)
    assert output =~ "runs_task"
    assert output =~ "changes=1"
    assert output =~ "artifacts=0"
    assert output =~ "backups=0"
  end

  test "verbose text output includes artifact and backup paths" do
    root =
      Path.join(System.tmp_dir!(), "host-kit-runs-verbose-#{System.unique_integer([:positive])}")

    runs_root = Path.join(root, "runs")
    backups_root = Path.join(root, "backups")
    up_path = Path.join(root, "up.plan.json")
    file_path = Path.join(root, "demo.txt")
    File.mkdir_p!(root)
    File.write!(file_path, "old")
    on_exit(fn -> File.rm_rf(root) end)

    before = %HostKit.Resources.File{path: file_path, content: "old"}
    after_resource = %HostKit.Resources.File{path: file_path, content: "new"}

    plan = %Plan{
      project: %HostKit.Project{name: :runs_verbose},
      changes: [
        %Change{
          action: :update,
          resource_id: {:file, file_path},
          before: before,
          after: after_resource
        }
      ]
    }

    assert :ok = HostKit.Plan.Artifact.save(up_path, plan)

    assert {:ok, _results} =
             HostKit.apply(plan,
               confirm: true,
               track: true,
               hostkit_runs_root: runs_root,
               hostkit_backups_root: backups_root,
               up_plan_artifact: up_path
             )

    assert {:ok, record} = HostKit.RunRecord.latest(hostkit_runs_root: runs_root)

    output = capture_io(fn -> Runs.run(["--runs-root", runs_root, "--verbose"]) end)
    assert output =~ "artifacts=1"
    assert output =~ "backups=1"
    assert output =~ "artifacts.up_plan="
    assert output =~ "backups."

    latest_output = capture_io(fn -> Runs.run(["--runs-root", runs_root, "--latest"]) end)
    assert latest_output =~ record.id

    id_output = capture_io(fn -> Runs.run(["--runs-root", runs_root, "--id", record.id]) end)
    assert id_output =~ record.id
  end
end
