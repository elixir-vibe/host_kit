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
  end
end
