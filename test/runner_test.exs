defmodule HostKit.RunnerTest do
  use ExUnit.Case, async: true

  defmodule CaptureRunner do
    @behaviour HostKit.Runner

    @impl true
    def cmd(command, args, opts) do
      send(opts[:test_pid], {:cmd, command, args, Keyword.delete(opts, :test_pid)})
      {"ok", 0}
    end
  end

  test "runs commands through module runners" do
    assert HostKit.Runner.cmd({CaptureRunner, test_pid: self()}, "echo", ["hello"], env: []) ==
             {"ok", 0}

    assert_received {:cmd, "echo", ["hello"], [env: []]}
  end

  test "local runner delegates to System.cmd" do
    assert {"hello\n", 0} = HostKit.Runner.Local.cmd("printf", ["hello\n"], [])
  end
end
