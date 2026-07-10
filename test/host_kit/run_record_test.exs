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
    assert Bitwise.band(File.stat!(record_path).mode, 0o777) == 0o600

    assert {:ok, [listed]} = HostKit.RunRecord.list(hostkit_runs_root: runs_root)
    assert listed.id == record["id"]
    assert {:ok, latest} = HostKit.RunRecord.latest(hostkit_runs_root: runs_root)
    assert latest.id == record["id"]
    assert {:ok, loaded} = HostKit.RunRecord.load(record["id"], hostkit_runs_root: runs_root)
    assert loaded.id == record["id"]
  end

  test "tracked applies use collision-resistant run ids" do
    root = Path.join(System.tmp_dir!(), "hostkit-run-ids-#{System.unique_integer([:positive])}")
    runs_root = Path.join(root, "runs")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    plan = %Plan{project: %HostKit.Project{name: :tracked}, changes: []}

    assert {:ok, []} =
             HostKit.apply(plan, confirm: true, track: true, hostkit_runs_root: runs_root)

    assert {:ok, []} =
             HostKit.apply(plan, confirm: true, track: true, hostkit_runs_root: runs_root)

    assert {:ok, [first, second]} = HostKit.RunRecord.list(hostkit_runs_root: runs_root)
    refute first.id == second.id
  end

  test "run listing reports corrupt records" do
    root =
      Path.join(System.tmp_dir!(), "hostkit-corrupt-run-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    File.write!(Path.join(root, "corrupt.json"), "not json")
    on_exit(fn -> File.rm_rf!(root) end)

    assert {:error, {:invalid_run_record, path, _reason}} =
             HostKit.RunRecord.list(hostkit_runs_root: root)

    assert path == Path.join(root, "corrupt.json")
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
    assert Bitwise.band(File.stat!(backup_path).mode, 0o777) == 0o600

    restored_plan = HostKit.RunRecord.apply_backups(plan, record)

    assert [
             %HostKit.Change{
               before: %HostKit.Resources.File{content: %HostKit.BackupRef{path: ^backup_path}}
             }
           ] = restored_plan.changes
  end

  test "tracked apply does not back up redacted structured config content" do
    root =
      Path.join(
        System.tmp_dir!(),
        "hostkit-runs-redacted-config-#{System.unique_integer([:positive])}"
      )

    path = Path.join(root, "app.ini")
    runs_root = Path.join(root, "runs")
    backups_root = Path.join(root, "backups")
    File.mkdir_p!(root)
    File.write!(path, "[server]\nTOKEN=actual-secret\n")
    on_exit(fn -> File.rm_rf(root) end)

    before =
      HostKit.Resources.ConfigFile.new(path, :ini,
        content: [server: [TOKEN: :redacted]],
        meta: %{actual_public_entries: %{}}
      )

    after_resource =
      HostKit.Resources.ConfigFile.new(path, :ini, content: [server: [DOMAIN: "example.test"]])

    plan = %Plan{
      project: %HostKit.Project{name: :tracked},
      changes: [
        %Change{
          action: :update,
          resource_id: {:ini, path},
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
    assert record.backups == %{}
    assert Path.wildcard(Path.join([backups_root, "**", "*.bak"])) == []
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

  test "backup-backed env files restore without re-rendering secrets" do
    root =
      Path.join(System.tmp_dir!(), "hostkit-env-backup-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    env_path = Path.join(root, "app.env")
    backup_path = Path.join(root, "backup.env")
    File.write!(env_path, "TOKEN=\"new\"\n")
    File.write!(backup_path, "TOKEN=\"old\"\n")

    env_file = %HostKit.Resources.EnvFile{
      path: env_path,
      entries: [{:secret, "TOKEN", HostKit.Secret.env("HOSTKIT_TEST_MISSING_SECRET")}],
      meta: %{content: %HostKit.BackupRef{path: backup_path}}
    }

    plan = %Plan{
      project: %HostKit.Project{name: :tracked},
      changes: [%Change{action: :update, resource_id: {:env_file, env_path}, after: env_file}]
    }

    assert {:ok, _results} = HostKit.apply(plan, confirm: true)
    assert File.read!(env_path) == "TOKEN=\"old\"\n"
  end

  test "prune removes old run records and payload directories" do
    root =
      Path.join(System.tmp_dir!(), "hostkit-runs-prune-#{System.unique_integer([:positive])}")

    runs_root = Path.join(root, "runs")
    File.mkdir_p!(runs_root)
    on_exit(fn -> File.rm_rf(root) end)

    old_artifact_dir = Path.join([runs_root, "artifacts", "old"])
    old_backup_dir = Path.join([root, "backups", "old"])
    File.mkdir_p!(old_artifact_dir)
    File.mkdir_p!(old_backup_dir)
    File.write!(Path.join(old_artifact_dir, "up.plan.json"), "{}")
    File.write!(Path.join(old_backup_dir, "file.bak"), "old")

    old = %HostKit.RunRecord{
      id: "20200101-000000-demo-up",
      project: "demo",
      direction: "up",
      applied_at: "2020-01-01T00:00:00Z",
      artifacts: %{"up_plan" => Path.join(old_artifact_dir, "up.plan.json")},
      backups: %{"{:file, \"/tmp/demo\"}" => Path.join(old_backup_dir, "file.bak")}
    }

    new = %HostKit.RunRecord{
      id: "20210101-000000-demo-up",
      project: "demo",
      direction: "up",
      applied_at: "2021-01-01T00:00:00Z"
    }

    File.write!(Path.join(runs_root, old.id <> ".json"), Jason.encode!(JSONCodec.dump(old)))
    File.write!(Path.join(runs_root, new.id <> ".json"), Jason.encode!(JSONCodec.dump(new)))

    assert {:ok, [^old]} =
             HostKit.RunRecord.prune(
               [hostkit_runs_root: runs_root, hostkit_backups_root: Path.join(root, "backups")],
               keep: 1
             )

    refute File.exists?(Path.join(runs_root, old.id <> ".json"))
    refute File.exists?(old_artifact_dir)
    refute File.exists?(old_backup_dir)
    assert File.exists?(Path.join(runs_root, new.id <> ".json"))
  end

  test "prune rejects payload paths outside tracking roots" do
    root =
      Path.join(
        System.tmp_dir!(),
        "hostkit-runs-safe-prune-#{System.unique_integer([:positive])}"
      )

    runs_root = Path.join(root, "runs")
    backups_root = Path.join(root, "backups")
    outside = Path.join(root, "outside")
    File.mkdir_p!(runs_root)
    File.mkdir_p!(outside)
    File.write!(Path.join(outside, "secret"), "keep")
    on_exit(fn -> File.rm_rf!(root) end)

    record = %HostKit.RunRecord{
      id: "20200101-000000-demo-up",
      project: "demo",
      direction: "up",
      applied_at: "2020-01-01T00:00:00Z",
      backups: %{"file" => Path.join(outside, "secret")}
    }

    File.write!(Path.join(runs_root, record.id <> ".json"), Jason.encode!(JSONCodec.dump(record)))

    assert {:error, {:unsafe_run_record_path, ^outside}} =
             HostKit.RunRecord.prune(
               [hostkit_runs_root: runs_root, hostkit_backups_root: backups_root],
               keep: 0
             )

    assert File.read!(Path.join(outside, "secret")) == "keep"
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
