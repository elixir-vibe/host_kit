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

    assert {:ok, [listed]} = HostKit.RunRecord.list(hostkit_runs_root: runs_root)
    assert listed.id == record["id"]
    assert {:ok, latest} = HostKit.RunRecord.latest(hostkit_runs_root: runs_root)
    assert latest.id == record["id"]
    assert {:ok, loaded} = HostKit.RunRecord.load(record["id"], hostkit_runs_root: runs_root)
    assert loaded.id == record["id"]
  end

  test "tracked apply stores backup payloads for previous file-like state" do
    root =
      Path.join(System.tmp_dir!(), "hostkit-runs-backups-#{System.unique_integer([:positive])}")

    path = Path.join(root, "demo.txt")
    runs_root = Path.join(root, "runs")
    backups_root = Path.join(root, "backups")
    File.mkdir_p!(root)
    File.write!(path, "old")
    on_exit(fn -> File.rm_rf(root) end)

    before = %HostKit.Resources.File{path: path, content: "old", mode: 0o644}
    after_resource = %HostKit.Resources.File{path: path, content: "new", mode: 0o644}

    plan = %Plan{
      project: %HostKit.Project{name: :tracked},
      changes: [
        %Change{
          action: :update,
          resource_id: {:file, path},
          before: before,
          after: after_resource
        }
      ]
    }

    assert {:ok, _results} =
             HostKit.apply(plan,
               confirm: true,
               track: true,
               hostkit_runs_root: runs_root,
               hostkit_backups_root: backups_root
             )

    assert {:ok, record} = HostKit.RunRecord.latest(hostkit_runs_root: runs_root)
    assert [{resource_id, backup_path}] = Map.to_list(record.backups)
    assert resource_id =~ ":file"
    assert File.read!(backup_path) == "old"

    restored_plan = HostKit.RunRecord.apply_backups(plan, record)

    assert [
             %HostKit.Change{
               before: %HostKit.Resources.File{content: %HostKit.BackupRef{path: ^backup_path}}
             }
           ] = restored_plan.changes
  end

  test "backup refs are applied to file-like resource metadata" do
    backup_path =
      Path.join(System.tmp_dir!(), "hostkit-backup-#{System.unique_integer([:positive])}")

    before = %HostKit.Proxy{
      name: :edge,
      provider: :gatehouse,
      path: "/tmp/gatehouse.exs",
      meta: %{content: "old proxy"}
    }

    plan = %Plan{
      project: %HostKit.Project{name: :tracked},
      changes: [
        %Change{action: :update, resource_id: {:proxy, :edge}, before: before, after: before}
      ]
    }

    record = %HostKit.RunRecord{backups: %{inspect({:proxy, :edge}) => backup_path}}

    restored_plan = HostKit.RunRecord.apply_backups(plan, record)

    assert [
             %HostKit.Change{
               before: %HostKit.Proxy{meta: %{content: %HostKit.BackupRef{path: ^backup_path}}}
             }
           ] = restored_plan.changes
  end

  test "backup-backed proxy resources restore captured content" do
    root =
      Path.join(System.tmp_dir!(), "hostkit-proxy-backup-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    proxy_path = Path.join(root, "gatehouse.exs")
    backup_path = Path.join(root, "backup.exs")
    File.write!(proxy_path, "new proxy")
    File.write!(backup_path, "old proxy")

    proxy = %HostKit.Proxy{
      name: :edge,
      provider: :gatehouse,
      path: proxy_path,
      meta: %{content: %HostKit.BackupRef{path: backup_path}}
    }

    plan = %Plan{
      project: %HostKit.Project{name: :tracked},
      changes: [%Change{action: :update, resource_id: {:proxy, :edge}, after: proxy}]
    }

    assert {:ok, _results} = HostKit.apply(plan, confirm: true)
    assert File.read!(proxy_path) == "old proxy"
  end

  test "tracked apply records plan artifact references" do
    root =
      Path.join(System.tmp_dir!(), "hostkit-runs-artifacts-#{System.unique_integer([:positive])}")

    path = Path.join(root, "demo.txt")
    runs_root = Path.join(root, "runs")
    up_plan = Path.join(root, "up.plan.json")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    plan = %Plan{
      project: %HostKit.Project{name: :tracked},
      changes: [
        %Change{
          action: :create,
          resource_id: {:file, path},
          after: %HostKit.Resources.File{path: path, content: "hello", mode: 0o644}
        }
      ]
    }

    assert :ok = HostKit.Plan.Artifact.save(up_plan, plan)

    assert {:ok, _results} =
             HostKit.apply(plan,
               confirm: true,
               track: true,
               hostkit_runs_root: runs_root,
               up_plan_artifact: up_plan
             )

    assert {:ok, record} = HostKit.RunRecord.latest(hostkit_runs_root: runs_root)
    copied = record.artifacts["up_plan"]
    assert copied == Path.join([runs_root, "artifacts", record.id, "up.plan.json"])
    assert File.read!(copied) == File.read!(up_plan)
  end
end
