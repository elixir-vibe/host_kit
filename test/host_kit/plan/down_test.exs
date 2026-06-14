defmodule HostKit.Plan.DownTest do
  use ExUnit.Case, async: true

  alias HostKit.{Change, Plan}

  test "down plan rolls back supported updates in reverse apply order" do
    root = Path.join(System.tmp_dir!(), "host-kit-rollback-#{System.unique_integer([:positive])}")
    first_path = Path.join(root, "first.txt")
    second_path = Path.join(root, "second.txt")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    File.write!(first_path, "old first")
    File.write!(second_path, "old second")

    first_before = %HostKit.Resources.File{path: first_path, content: "old first", mode: 0o644}
    first_after = %HostKit.Resources.File{path: first_path, content: "new first", mode: 0o644}
    second_before = %HostKit.Resources.File{path: second_path, content: "old second", mode: 0o644}
    second_after = %HostKit.Resources.File{path: second_path, content: "new second", mode: 0o644}

    plan = %Plan{
      project: %HostKit.Project{name: :rollback_test},
      changes: [
        %Change{
          action: :update,
          resource_id: {:file, first_path},
          before: first_before,
          after: first_after
        },
        %Change{
          action: :update,
          resource_id: {:file, second_path},
          before: second_before,
          after: second_after
        }
      ]
    }

    assert {:ok, results} = HostKit.apply(plan, confirm: true)

    assert Enum.map(results, & &1.change.resource_id) == [
             {:file, first_path},
             {:file, second_path}
           ]

    assert File.read!(first_path) == "new first"
    assert File.read!(second_path) == "new second"

    assert {:ok, down_plan} = HostKit.down(plan)

    assert Enum.map(down_plan.changes, & &1.resource_id) == [
             {:file, second_path},
             {:file, first_path}
           ]

    assert {:ok, _results} = HostKit.apply(down_plan, confirm: true)
    assert File.read!(first_path) == "old first"
    assert File.read!(second_path) == "old second"
  end

  test "down plan can delete supported resources created by the up plan" do
    root =
      Path.join(
        System.tmp_dir!(),
        "host-kit-rollback-delete-#{System.unique_integer([:positive])}"
      )

    path = Path.join(root, "created.txt")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    resource = %HostKit.Resources.File{path: path, content: "created", mode: 0o644}

    plan = %Plan{
      project: %HostKit.Project{name: :rollback_test},
      changes: [%Change{action: :create, resource_id: {:file, path}, after: resource}]
    }

    assert {:ok, _results} = HostKit.apply(plan, confirm: true)
    assert File.exists?(path)

    assert {:ok, down_plan} = HostKit.down(plan)
    assert [%Change{action: :delete, before: ^resource, after: nil}] = down_plan.changes
    assert {:ok, _results} = HostKit.apply(down_plan, confirm: true)
    refute File.exists?(path)
  end

  test "down plan only deletes created directories when explicitly opted in" do
    keep = %HostKit.Resources.Directory{path: "/tmp/keep"}
    delete = %HostKit.Resources.Directory{path: "/tmp/delete", rollback: :delete_if_created}

    plan = %Plan{
      project: %HostKit.Project{name: :rollback_test},
      changes: [
        %Change{action: :create, resource_id: {:directory, keep.path}, after: keep},
        %Change{action: :create, resource_id: {:directory, delete.path}, after: delete}
      ]
    }

    assert {:ok, down_plan} = HostKit.down(plan)

    assert [%Change{action: :delete, resource_id: {:directory, "/tmp/delete"}}] =
             down_plan.changes

    assert [%HostKit.Diagnostic{resource_id: {:directory, "/tmp/keep"}}] =
             down_plan.diagnostics.warnings
  end

  test "down plan uses explicit command down steps" do
    migrate =
      HostKit.Resources.Command.new(:migrate,
        exec: {"bin/app", ["eval", "App.Release.migrate()"]},
        cwd: "/opt/app",
        env: %{"MIX_ENV" => "prod"},
        down: {"bin/app", ["eval", "App.Release.rollback()"]}
      )

    plan = %Plan{
      project: %HostKit.Project{name: :rollback_test},
      changes: [%Change{action: :create, resource_id: {:command, :migrate}, after: migrate}]
    }

    assert {:ok, down_plan} = HostKit.down(plan)

    assert [
             %Change{
               action: :create,
               resource_id: {:command, "migrate_down"},
               after: %HostKit.Resources.Command{
                 name: "migrate_down",
                 exec: {"bin/app", ["eval", "App.Release.rollback()"]},
                 cwd: "/opt/app",
                 env: %{"MIX_ENV" => "prod"}
               }
             }
           ] = down_plan.changes
  end

  test "down plan treats command noop rollback as explicit" do
    command =
      HostKit.Resources.Command.new(:warm_cache,
        exec: {"bin/app", ["eval", "App.Cache.warm()"]},
        down: :noop
      )

    plan = %Plan{
      project: %HostKit.Project{name: :rollback_test},
      changes: [%Change{action: :create, resource_id: {:command, :warm_cache}, after: command}]
    }

    assert {:ok, down_plan} = HostKit.down(plan)
    assert down_plan.changes == []
    assert down_plan.diagnostics.warnings == []
  end

  test "down plan records warnings for irreversible resources" do
    package = %HostKit.Resources.Package{name: :git}

    plan = %Plan{
      project: %HostKit.Project{name: :rollback_test},
      changes: [%Change{action: :create, resource_id: {:package, :git}, after: package}]
    }

    assert {:ok, down_plan} = HostKit.down(plan)
    assert down_plan.changes == []

    assert [%HostKit.Diagnostic{code: :irreversible_change, resource_id: {:package, :git}}] =
             down_plan.diagnostics.warnings
  end

  test "down plan can be filtered to part of the original plan" do
    first = %HostKit.Resources.File{path: "/tmp/first", content: "old"}
    second = %HostKit.Resources.File{path: "/tmp/second", content: "old"}

    plan = %Plan{
      project: %HostKit.Project{name: :rollback_test},
      changes: [
        %Change{
          action: :update,
          resource_id: {:file, "/tmp/first"},
          before: first,
          after: %{first | content: "new"}
        },
        %Change{
          action: :update,
          resource_id: {:file, "/tmp/second"},
          before: second,
          after: %{second | content: "new"}
        }
      ]
    }

    assert {:ok, down_plan} = HostKit.down(plan, only: [{:file, "/tmp/first"}])
    assert Enum.map(down_plan.changes, & &1.resource_id) == [{:file, "/tmp/first"}]
  end
end
