defmodule HostKit.CommandTest do
  use ExUnit.Case, async: false

  test "command resources apply shell steps and honor creates" do
    root = Path.join(System.tmp_dir!(), "hostkit-command-#{System.unique_integer([:positive])}")
    path = Path.join(root, "hello.txt")

    on_exit(fn -> File.rm_rf(root) end)

    project = %HostKit.Project{
      name: :command_test,
      services: [
        %HostKit.Service{
          name: :demo,
          resources: [
            HostKit.Resources.Directory.new(root),
            HostKit.Resources.Command.new(:write_hello,
              run: "printf hello > #{path}",
              creates: path
            )
          ]
        }
      ]
    }

    {:ok, plan} = HostKit.plan(project)
    assert {:ok, _results} = HostKit.apply(plan, confirm: true)
    assert File.read!(path) == "hello"

    File.write!(path, "kept")
    assert {:ok, _results} = HostKit.apply(plan, confirm: true)
    assert File.read!(path) == "kept"
  end
end
