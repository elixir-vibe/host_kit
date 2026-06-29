defmodule HostKit.BackupTest do
  use ExUnit.Case, async: true

  test "backup metadata attaches to existing services and jobs without generated scripts" do
    source = """
    use HostKit.DSL

    project :prod do
      prefixes unit: "toys-", user: "toys-"

      service :llm_proxy, path: "llm-proxy" do
        account system: true
        storage :state, path: "/var/lib/toys/llm-proxy", backup: true
        storage :config, path: "/etc/toys/llm-proxy", backup: true, secret: true

        backup do
          consistency :stop
          verify storage_path(:state), "main.duckdb"
        end
      end

      service :backups do
        storage :archives, path: "/srv/toys/backups", mode: 0o700

        job "toys-backup-local" do
          backup destination: storage_path(:archives), config: "/opt/toys/src/elixir-toys/infra/config.exs", cwd: "/opt/toys/src/host_kit" do
            include :llm_proxy
            include :hex_mirror_metadata, paths: ["/srv/toys/hex-mirror/public_key", "/srv/toys/hex-mirror/names"]
            keep days: 14
          end
        end

        schedule "toys-backup-local" do
          daily at: ~T[02:30:00]
          persistent true
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    resources = HostKit.Project.resources(project)

    refute Enum.any?(
             resources,
             &match?(%HostKit.Resources.File{path: "/usr/local/sbin/toys-backup-local"}, &1)
           )

    assert %HostKit.Backup.Service{consistency: :stop, verify: verify} =
             project.services
             |> Enum.find(&(&1.name == :llm_proxy))
             |> then(& &1.meta.backup)

    assert verify == ["/var/lib/toys/llm-proxy/main.duckdb"]

    assert %HostKit.Systemd.Service{service: service_opts, meta: %{backup: backup}} =
             Enum.find(
               resources,
               &match?(%HostKit.Systemd.Service{name: "toys-backup-local.service"}, &1)
             )

    assert %HostKit.Backup.Job{
             destination: "/srv/toys/backups",
             includes: [
               {:service, :llm_proxy},
               {:paths, :hex_mirror_metadata,
                ["/srv/toys/hex-mirror/public_key", "/srv/toys/hex-mirror/names"]}
             ],
             keep: [days: 14]
           } = backup

    assert service_opts[:type] == :oneshot
    assert service_opts[:working_directory] == "/opt/toys/src/host_kit"

    assert service_opts[:exec_start] ==
             "mix host_kit.backup.run toys-backup-local /opt/toys/src/elixir-toys/infra/config.exs"

    assert {:ok, rendered} =
             HostKit.Render.render(project, {:systemd_service, "toys-backup-local.service"})

    assert rendered =~
             "ExecStart=mix host_kit.backup.run toys-backup-local /opt/toys/src/elixir-toys/infra/config.exs"
  end

  test "runner stops active service backups and restarts after archive verification" do
    root =
      Path.join(System.tmp_dir!(), "hostkit-backup-service-#{System.unique_integer([:positive])}")

    Process.put(:backup_test_root, root)
    state = Path.join(root, "state")
    destination = Path.join(root, "backups")
    File.mkdir_p!(state)
    File.write!(Path.join(state, "main.duckdb"), "db")
    parent = self()

    runner = fn
      "systemctl", args, _opts ->
        send(parent, {:systemctl, args})
        {"", 0}

      command, args, opts ->
        System.cmd(command, args, opts)
    end

    service = %HostKit.Service{
      name: :llm_proxy,
      identity: "llm-proxy",
      meta: %{
        storage: %{
          state: %HostKit.Storage.Volume{name: :state, path: state, backup: true}
        },
        backup: %HostKit.Backup.Service{
          consistency: :stop,
          verify: [Path.join(state, "main.duckdb")]
        }
      }
    }

    project = %HostKit.Project{
      name: :demo,
      services: [service],
      resources: [
        %HostKit.Systemd.Service{
          name: "demo-backup.service",
          meta: %{
            backup: %HostKit.Backup.Job{
              name: "demo-backup.service",
              destination: destination,
              config: "/tmp/demo.exs",
              includes: [{:service, :llm_proxy}]
            }
          }
        }
      ],
      conventions: HostKit.Conventions.new(prefixes: %{unit: "toys-"})
    }

    assert {:ok, result} =
             HostKit.Backup.Runner.run(project, "demo-backup",
               stamp: "20260629T130000Z",
               runner: runner,
               interval: 0
             )

    assert [archive] = result.archives
    assert archive.unit == "toys-llm-proxy.service"
    assert archive.verified == [String.trim_leading(Path.join(state, "main.duckdb"), "/")]

    assert_received {:systemctl, ["is-active", "--quiet", "toys-llm-proxy.service"]}
    assert_received {:systemctl, ["stop", "toys-llm-proxy.service"]}
    assert_received {:systemctl, ["start", "toys-llm-proxy.service"]}
  after
    if root = Process.get(:backup_test_root), do: File.rm_rf!(root)
  end

  test "runner archives included paths and writes checksum and manifest" do
    root = Path.join(System.tmp_dir!(), "hostkit-backup-#{System.unique_integer([:positive])}")
    Process.put(:backup_test_root, root)
    source = Path.join(root, "source")
    destination = Path.join(root, "backups")
    File.mkdir_p!(source)
    File.write!(Path.join(source, "data.txt"), "hello")

    project = %HostKit.Project{
      name: :demo,
      resources: [
        %HostKit.Systemd.Service{
          name: "demo-backup.service",
          meta: %{
            backup: %HostKit.Backup.Job{
              name: "demo-backup.service",
              destination: destination,
              config: "/tmp/demo.exs",
              includes: [{:path, source}]
            }
          }
        }
      ]
    }

    assert {:ok, result} =
             HostKit.Backup.Runner.run(project, "demo-backup", stamp: "20260629T120000Z")

    assert [archive] = result.archives
    assert File.exists?(archive.path)
    assert File.exists?(archive.checksum)
    assert File.exists?(result.manifest)

    assert {:ok, members} = HostKit.Backup.Archive.members(archive.path)
    assert String.trim_leading(source, "/") in members
  after
    if root = Process.get(:backup_test_root), do: File.rm_rf!(root)
  end
end
