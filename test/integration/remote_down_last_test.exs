defmodule HostKit.RemoteDownLastIntegrationTest do
  use HostKit.Case, async: false

  import ExUnit.CaptureIO

  @moduletag :integration

  @tag timeout: 300_000
  test "tracked remote apply can generate and apply down --last" do
    case HostKit.IntegrationTarget.selected() do
      {:ok, target} -> run_remote_down_last(target)
      {:skip, reason} -> IO.puts("Skipping remote down --last integration: #{reason}")
    end
  end

  defp run_remote_down_last(%HostKit.IntegrationTarget{host: host, cleanup: cleanup}) do
    unique = System.unique_integer([:positive])
    root = "/tmp/hostkit-down-last-integration-#{unique}"
    file_path = "#{root}/message.txt"
    runs_root = "#{root}/runs"
    backups_root = "#{root}/backups"
    config_path = Path.join(System.tmp_dir!(), "hostkit-down-last-#{unique}.exs")
    up_path = Path.join(System.tmp_dir!(), "hostkit-down-last-#{unique}.up.plan.json")
    down_path = Path.join(System.tmp_dir!(), "hostkit-down-last-#{unique}.down.plan.json")

    cleanup.(root)

    on_exit(fn ->
      cleanup.(root)
      File.rm(config_path)
      File.rm(up_path)
      File.rm(down_path)
      Mix.Task.reenable("host_kit.plan")
      Mix.Task.reenable("host_kit.apply")
      Mix.Task.reenable("host_kit.runs")
      Mix.Task.reenable("host_kit.down")
    end)

    File.write!(config_path, project_source(host, root, file_path))

    assert :ok = remote_cmd(host, "mkdir", ["-p", root])
    assert :ok = remote_write(host, file_path, "old\n")

    capture_io(fn ->
      Mix.Tasks.HostKit.Plan.run(["--host", to_string(host.name), "--out", up_path, config_path])
    end)

    capture_io(fn ->
      Mix.Tasks.HostKit.Apply.run([
        "--host",
        to_string(host.name),
        "--plan",
        up_path,
        "--confirm",
        "--track",
        "--runs-root",
        runs_root,
        "--backups-root",
        backups_root,
        config_path
      ])
    end)

    assert {:ok, "new\n"} = remote_read(host, file_path)

    runs_output =
      capture_io(fn ->
        Mix.Tasks.HostKit.Runs.run([
          "--host",
          to_string(host.name),
          "--runs-root",
          runs_root,
          "--verbose",
          config_path
        ])
      end)

    assert runs_output =~ "backups=1"

    capture_io(fn ->
      Mix.Tasks.HostKit.Down.run([
        "--host",
        to_string(host.name),
        "--last",
        "--runs-root",
        runs_root,
        "--out",
        down_path,
        config_path
      ])
    end)

    capture_io(fn ->
      Mix.Tasks.HostKit.Apply.run([
        "--host",
        to_string(host.name),
        "--plan",
        down_path,
        "--confirm",
        config_path
      ])
    end)

    assert {:ok, "old\n"} = remote_read(host, file_path)
  end

  defp project_source(host, root, file_path) do
    host_name = host.name
    hostname = host.hostname
    user = host.user
    sudo = host.sudo
    ssh_opts = host.meta[:ssh] || []

    quote do
      use HostKit.DSL

      project :remote_down_last do
        host unquote(host_name) do
          hostname(unquote(hostname))
          user(unquote(user))
          sudo(unquote(sudo))
          ssh(unquote(Macro.escape(ssh_opts)))
        end

        service :demo do
          directory(unquote(root), mode: 0o755, rollback: :delete_if_created)
          file(unquote(file_path), content: "new\n", mode: 0o644)
        end
      end
    end
    |> Macro.to_string()
    |> Kernel.<>("\n")
  end

  defp remote_write(host, path, content) do
    encoded = Base.encode64(content)

    remote_cmd(host, "sh", [
      "-c",
      "printf %s #{encoded} | base64 -d > #{HostKit.Shell.escape(path)}"
    ])
  end

  defp remote_read(host, path) do
    case remote_cmd_output(host, "cat", [path]) do
      {content, 0} -> {:ok, content}
      {output, status} -> {:error, {status, output}}
    end
  end

  defp remote_cmd(host, command, args) do
    case remote_cmd_output(host, command, args) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {status, output}}
    end
  end

  defp remote_cmd_output(host, command, args) do
    {:ok, conn} = HostKit.Runner.SSH.Connection.open(HostKit.Host.ssh_options(host))

    try do
      HostKit.Runner.SSH.Connection.cmd(command, args, conn: conn, stderr_to_stdout: true)
    after
      HostKit.Runner.SSH.Connection.close(conn)
    end
  end
end
