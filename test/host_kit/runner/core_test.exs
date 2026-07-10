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

  test "local runner creates directories through sudo when requested" do
    cmd_fun = fn command, args, _opts ->
      send(self(), {:local_cmd, command, args})
      {"", 0}
    end

    assert :ok = HostKit.Runner.Local.mkdir_p("/root/demo", sudo: true, cmd_fun: cmd_fun)
    assert_received {:local_cmd, "sudo", ["mkdir", "-p", "/root/demo"]}
  end

  test "local runner writes files atomically with restrictive permissions" do
    root = Path.join(System.tmp_dir!(), "hostkit-runner-#{System.unique_integer([:positive])}")
    path = Path.join(root, "secret")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    assert :ok = HostKit.Runner.Local.write_file(path, "secret", mode: 0o640)
    assert File.read!(path) == "secret"
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o640
    assert Path.wildcard(path <> ".hostkit-*") == []
  end

  test "local runner stages sudo writes with final metadata before rename" do
    cmd_fun = fn command, args, _opts ->
      send(self(), {:local_cmd, command, args})

      case {command, args} do
        {"sudo", ["install", "-m", "0640", "-o", "root", "-g", "app", "--", source, _target]} ->
          send(self(), {:temp_content, source, File.read!(source), File.stat!(source).mode})

        _other ->
          :ok
      end

      {"", 0}
    end

    assert :ok =
             HostKit.Runner.Local.write_file("/root/demo", "hello",
               sudo: true,
               owner: "root",
               group: "app",
               mode: 0o640,
               cmd_fun: cmd_fun
             )

    assert_received {:local_cmd, "sudo",
                     [
                       "install",
                       "-m",
                       "0640",
                       "-o",
                       "root",
                       "-g",
                       "app",
                       "--",
                       source_path,
                       target_path
                     ]}

    assert_received {:temp_content, ^source_path, "hello", source_mode}
    assert Bitwise.band(source_mode, 0o777) == 0o600
    assert_received {:local_cmd, "sudo", ["mv", "-f", "--", ^target_path, "/root/demo"]}
    assert_received {:local_cmd, "sudo", ["rm", "-f", "--", ^target_path]}
    refute File.exists?(source_path)
  end
end
