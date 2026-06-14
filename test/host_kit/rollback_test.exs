defmodule HostKit.RollbackTest do
  use ExUnit.Case, async: true

  alias HostKit.{Change, Plan}

  test "rolls back supported updates in reverse apply order" do
    root = Path.join(System.tmp_dir!(), "host-kit-rollback-#{System.unique_integer([:positive])}")
    path = Path.join(root, "config.txt")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    File.write!(path, "old")

    before = %HostKit.Resources.File{path: path, content: "old", mode: 0o644}
    after_resource = %HostKit.Resources.File{path: path, content: "new", mode: 0o644}

    plan = %Plan{
      changes: [
        %Change{
          action: :update,
          resource_id: {:file, path},
          before: before,
          after: after_resource
        }
      ]
    }

    assert {:ok, results} = HostKit.apply(plan, confirm: true)
    assert File.read!(path) == "new"

    assert {:ok, [%{status: :rolled_back}]} = HostKit.rollback(results)
    assert File.read!(path) == "old"
  end

  test "skips created resources because there is no previous state" do
    change = %Change{
      action: :create,
      resource_id: {:file, "/tmp/created"},
      before: nil,
      after: %HostKit.Resources.File{path: "/tmp/created", content: "created"}
    }

    assert {:ok, [%{status: :skipped, reason: :no_previous_state}]} =
             HostKit.rollback([%{change: change, status: :applied}])
  end
end
