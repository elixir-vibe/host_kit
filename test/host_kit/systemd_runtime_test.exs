defmodule HostKit.SystemdRuntimeTest do
  use ExUnit.Case, async: true

  alias HostKit.SystemdRuntime

  defmodule Runner do
    @behaviour HostKit.Runner

    @impl true
    def cmd(command, args, opts) do
      send(opts[:test_pid], {:cmd, command, args})
      {"", 0}
    end

    @impl true
    def mkdir_p(_path, _opts), do: :ok

    @impl true
    def write_file(_path, _content, _opts), do: :ok
  end

  test "runner fallback reloads systemd without shell script" do
    assert :ok = SystemdRuntime.reload(runner: {Runner, test_pid: self()})
    assert_received {:cmd, "systemctl", ["daemon-reload"]}
    refute_received {:cmd, "sh", _args}
  end

  test "runner fallback restarts units with separate systemctl calls" do
    check = %HostKit.Readiness.Systemd{unit: "app.service", restart: true, kill: true}

    assert :ok = SystemdRuntime.restart(check, runner: {Runner, test_pid: self()})

    assert_received {:cmd, "systemctl", ["kill", "--kill-who=all", "app.service"]}
    assert_received {:cmd, "systemctl", ["reset-failed", "app.service"]}
    assert_received {:cmd, "systemctl", ["restart", "app.service"]}
    refute_received {:cmd, "sh", _args}
  end

  test "runner fallback checks active state without shell script" do
    assert :ok = SystemdRuntime.active?("app.service", runner: {Runner, test_pid: self()})
    assert_received {:cmd, "systemctl", ["is-active", "--quiet", "app.service"]}
    refute_received {:cmd, "sh", _args}
  end
end
