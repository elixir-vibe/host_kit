defmodule HostKit.RunStampTest do
  use ExUnit.Case, async: false

  test "run stamps include source identities" do
    source = %HostKit.Resources.Source{
      name: :app,
      uri: "https://github.com/example/app.git",
      ref: "main",
      ref_kind: :branch,
      revision: "abc123",
      checkout: "/opt/app/source",
      meta: %{tree: "def456"}
    }

    command =
      HostKit.Resources.Command.new(:build,
        exec: ["true"],
        inputs: [HostKit.Source.Ref.new(:app)]
      )

    stamp = HostKit.RunStamp.desired(command, resources: [source])

    assert stamp["inputs"] == []
    assert stamp["source_inputs"]["app"]["revision"] == "abc123"
    assert stamp["source_inputs"]["app"]["tree"] == "def456"
  end

  test "run resources can be current via input/output stamp" do
    root = Path.join(System.tmp_dir!(), "hostkit-run-stamp-#{System.unique_integer([:positive])}")
    input = Path.join(root, "input.txt")
    stamp = Path.join(root, ".hostkit/build.json")

    on_exit(fn -> File.rm_rf(root) end)
    File.mkdir_p!(root)
    File.write!(input, "one")

    project = %HostKit.Project{
      name: :run_stamp,
      services: [
        %HostKit.Service{
          name: :demo,
          resources: [
            HostKit.Resources.Command.new(:copy,
              exec: ["sh", "-c", "cp input.txt output.txt"],
              cwd: root,
              inputs: ["input.txt"],
              outputs: ["output.txt"],
              stamp: stamp
            )
          ]
        }
      ]
    }

    assert {:ok, first_plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%HostKit.Change{action: :create}] = first_plan.changes
    assert {:ok, _results} = HostKit.apply(first_plan, confirm: true)

    assert {:ok, second_plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%HostKit.Change{action: :no_op}] = second_plan.changes

    File.write!(input, "two")
    assert {:ok, third_plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%HostKit.Change{action: :create}] = third_plan.changes
  end
end
