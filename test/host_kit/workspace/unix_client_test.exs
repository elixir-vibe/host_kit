defmodule HostKit.WorkspaceUnixClientTest do
  use ExUnit.Case, async: true

  test "sends and receives Erlang terms over Unix socket" do
    socket =
      Path.join(System.tmp_dir!(), "host-kit-agent-#{System.unique_integer([:positive])}.sock")

    parent = self()

    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, active: false, packet: 4, ifaddr: {:local, socket}])

    task =
      Task.async(fn ->
        {:ok, client} = :gen_tcp.accept(listen)
        {:ok, payload} = :gen_tcp.recv(client, 0, 1_000)
        send(parent, {:payload, :erlang.binary_to_term(payload, [:safe])})
        :ok = :gen_tcp.send(client, :erlang.term_to_binary(%{status: :ok}))
        :gen_tcp.close(client)
        :gen_tcp.close(listen)
      end)

    assert {:ok, %{status: :ok}} =
             HostKit.Workspace.Agent.UnixClient.status(socket, timeout: 1_000)

    assert_received {:payload, :status}
    Task.await(task)
    File.rm(socket)
  end

  test "decodes check results from terms" do
    socket =
      Path.join(
        System.tmp_dir!(),
        "host-kit-agent-checks-#{System.unique_integer([:positive])}.sock"
      )

    check = HostKit.Monitor.Check.new(type: :mix)

    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, active: false, packet: 4, ifaddr: {:local, socket}])

    task =
      Task.async(fn ->
        {:ok, client} = :gen_tcp.accept(listen)
        {:ok, _payload} = :gen_tcp.recv(client, 0, 1_000)
        result = HostKit.Monitor.Result.ok(check, %{exit_status: 0})
        :ok = :gen_tcp.send(client, :erlang.term_to_binary({:ok, [result]}))
        :gen_tcp.close(client)
        :gen_tcp.close(listen)
      end)

    assert {:ok, [result]} =
             HostKit.Workspace.Agent.UnixClient.run_checks(socket, [check], timeout: 1_000)

    assert result.status == :ok
    assert result.observed == %{exit_status: 0}
    Task.await(task)
    File.rm(socket)
  end
end
