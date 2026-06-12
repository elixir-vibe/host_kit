defmodule HostKit.RunnerTest do
  use ExUnit.Case, async: true

  defmodule CaptureRunner do
    @behaviour HostKit.Runner

    @impl true
    def cmd(command, args, opts) do
      send(opts[:test_pid], {:cmd, command, args, Keyword.delete(opts, :test_pid)})
      {"ok", 0}
    end

    @impl true
    def mkdir_p(path, opts) do
      send(opts[:test_pid], {:mkdir_p, path, Keyword.delete(opts, :test_pid)})
      :ok
    end

    @impl true
    def write_file(path, content, opts) do
      send(opts[:test_pid], {:write_file, path, content, Keyword.delete(opts, :test_pid)})
      :ok
    end
  end

  test "runs commands through module runners" do
    assert HostKit.Runner.cmd({CaptureRunner, test_pid: self()}, "echo", ["hello"], env: []) ==
             {"ok", 0}

    assert_received {:cmd, "echo", ["hello"], [env: []]}
  end

  test "runs filesystem operations through module runners" do
    runner = {CaptureRunner, test_pid: self()}

    assert HostKit.Runner.mkdir_p(runner, "/tmp/demo", foo: :bar) == :ok
    assert HostKit.Runner.write_file(runner, "/tmp/demo/file", "hello", foo: :bar) == :ok

    assert_received {:mkdir_p, "/tmp/demo", [foo: :bar]}
    assert_received {:write_file, "/tmp/demo/file", "hello", [foo: :bar]}
  end

  test "local runner delegates to System.cmd" do
    assert {"hello\n", 0} = HostKit.Runner.Local.cmd("printf", ["hello\n"], [])
  end
end
