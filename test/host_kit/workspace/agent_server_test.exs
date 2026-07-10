defmodule HostKit.WorkspaceAgentServerTest do
  use ExUnit.Case, async: true

  test "serves status and exec over Unix socket" do
    dir = Path.join(System.tmp_dir!(), "host-kit-ws-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    socket = Path.join(dir, "agent.sock")

    {:ok, pid} =
      HostKit.Workspace.Agent.Server.start_link(socket: socket, workspace: dir, name: nil)

    assert {:ok, %{status: :ok}} = HostKit.Workspace.Agent.UnixClient.status(socket, [])
    assert {:ok, %File.Stat{mode: mode}} = File.stat(socket)
    assert Bitwise.band(mode, 0o777) == 0o600

    assert {:ok, %{exit_status: 0, stdout: output}} =
             HostKit.Workspace.Agent.UnixClient.exec(socket, ["pwd"], [])

    assert String.ends_with?(String.trim(output), Path.basename(dir))

    GenServer.stop(pid)
    File.rm_rf!(dir)
  end

  test "bounds command output while preserving exit status" do
    dir = Path.join(System.tmp_dir!(), "host-kit-ws-output-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    socket = Path.join(dir, "agent.sock")

    {:ok, pid} =
      HostKit.Workspace.Agent.Server.start_link(
        socket: socket,
        workspace: dir,
        max_output: 5,
        name: nil
      )

    assert {:ok, %{exit_status: 0, stdout: "12345"}} =
             HostKit.Workspace.Agent.UnixClient.exec(socket, ["printf", "123456789"], [])

    GenServer.stop(pid)
    File.rm_rf!(dir)
  end

  test "runs inside checks" do
    dir = Path.join(System.tmp_dir!(), "host-kit-ws-checks-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    socket = Path.join(dir, "agent.sock")

    {:ok, pid} =
      HostKit.Workspace.Agent.Server.start_link(socket: socket, workspace: dir, name: nil)

    check = HostKit.Monitor.Check.new(type: :git)
    assert {:ok, [result]} = HostKit.Workspace.Agent.UnixClient.run_checks(socket, [check], [])
    assert result.status == :error

    GenServer.stop(pid)
    File.rm_rf!(dir)
  end
end
