defmodule HostKit.TelemetryRuntimeTest do
  use ExUnit.Case, async: false

  defmodule TelemetryRunner do
    @behaviour HostKit.Runner

    @impl true
    def cmd(_command, _args, _opts), do: {"ok", 0}

    @impl true
    def mkdir_p(_path, _opts), do: :ok

    @impl true
    def write_file(_path, _content, _opts), do: :ok
  end

  setup do
    test_pid = self()
    handler_id = {__MODULE__, make_ref()}

    events = [
      [:host_kit, :runner, :cmd, :start],
      [:host_kit, :runner, :cmd, :stop]
    ]

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_event/4,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  def handle_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry_event, event, measurements, metadata})
  end

  test "runner commands emit telemetry with duration and status" do
    assert {"ok", 0} = HostKit.Runner.cmd(TelemetryRunner, "echo", ["hello"], [])

    assert_received {:telemetry_event, [:host_kit, :runner, :cmd, :start], start_measurements,
                     start_metadata}

    assert is_integer(start_measurements.system_time)
    assert start_metadata.command == "echo"
    assert start_metadata.args == ["hello"]
    assert start_metadata.runner == TelemetryRunner

    assert_received {:telemetry_event, [:host_kit, :runner, :cmd, :stop], stop_measurements,
                     stop_metadata}

    assert is_integer(stop_measurements.duration)
    assert stop_metadata.status == 0
    assert stop_metadata.command == "echo"
  end
end
