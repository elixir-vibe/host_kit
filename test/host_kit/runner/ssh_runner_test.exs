defmodule HostKit.Runner.SSHTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias HostKit.Runner.SSH.Connection

  test "module exists as a HostKit runner" do
    Code.ensure_loaded!(HostKit.Runner.SSH)

    assert function_exported?(HostKit.Runner.SSH, :cmd, 3)
    assert function_exported?(HostKit.Runner.SSH, :mkdir_p, 2)
    assert function_exported?(HostKit.Runner.SSH, :write_file, 3)
  end

  test "connection runner exposes reusable connection API" do
    Code.ensure_loaded!(HostKit.Runner.SSH.Connection)

    assert function_exported?(HostKit.Runner.SSH.Connection, :open, 1)
    assert function_exported?(HostKit.Runner.SSH.Connection, :close, 1)
    assert function_exported?(HostKit.Runner.SSH.Connection, :cmd, 3)
  end

  test "connection open retries transient failures when ssh retry is configured" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    connect_fun = fn _host, _port, _ssh_opts, _timeout ->
      Agent.get_and_update(attempts, fn count -> {count, count + 1} end)
      |> case do
        0 -> {:error, :econnrefused}
        _ -> {:ok, :fake_connection}
      end
    end

    capture_log(fn ->
      assert {:ok, :fake_connection} =
               Connection.open(
                 host: "example.test",
                 user: "root",
                 connect_fun: connect_fun,
                 retry: [attempts: 3, base_delay: 0],
                 reporter: self()
               )
    end)

    assert Agent.get(attempts, & &1) == 2

    assert_receive {HostKit.Apply,
                    %HostKit.Apply.Event{
                      type: :transport_retry_started,
                      details: %{transport: :ssh, attempt: 2, attempts: 3, delay_ms: 0}
                    }}

    assert_receive {HostKit.Apply,
                    %HostKit.Apply.Event{
                      type: :transport_retry_succeeded,
                      details: %{transport: :ssh, attempt: 2, attempts: 3}
                    }}
  end

  test "connection open logs retry attempts for later collection" do
    connect_fun = fn _host, _port, _ssh_opts, _timeout -> {:error, :timeout} end

    log =
      capture_log(fn ->
        assert {:error, :timeout} =
                 Connection.open(
                   host: "example.test",
                   user: "root",
                   connect_fun: connect_fun,
                   retry: [attempts: 2, base_delay: 0]
                 )
      end)

    assert log =~ "ssh reconnect attempt=2/2 after 0ms"
    assert log =~ "ssh reconnect attempt=2/2 attempts exhausted"
  end

  test "connection open reports exhausted ssh retry attempts" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    connect_fun = fn _host, _port, _ssh_opts, _timeout ->
      Agent.update(attempts, &(&1 + 1))
      {:error, :timeout}
    end

    capture_log(fn ->
      assert {:error, :timeout} =
               Connection.open(
                 host: "example.test",
                 user: "root",
                 connect_fun: connect_fun,
                 retry: [attempts: 2, base_delay: 0],
                 reporter: self()
               )
    end)

    assert Agent.get(attempts, & &1) == 2
    assert_receive {HostKit.Apply, %HostKit.Apply.Event{type: :transport_retry_started}}
    assert_receive {HostKit.Apply, %HostKit.Apply.Event{type: :transport_retry_exhausted}}
  end
end
