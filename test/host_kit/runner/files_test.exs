defmodule HostKit.Runner.FilesTest do
  use ExUnit.Case, async: true

  defmodule FakeRunner do
    @behaviour HostKit.Runner

    @impl true
    def cmd(command, args, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:cmd, command, args, opts})
      {Base.encode64("secret"), 0}
    end

    @impl true
    def mkdir_p(_path, _opts), do: :ok

    @impl true
    def write_file(_path, _content, _opts), do: :ok
  end

  test "reads local files directly without sudo" do
    path =
      Path.join(System.tmp_dir!(), "hostkit-runner-files-#{System.unique_integer([:positive])}")

    File.write!(path, "hello")
    on_exit(fn -> File.rm(path) end)

    assert HostKit.Runner.Files.read_file(path) == {:ok, "hello"}
  end

  test "reads through runner with sudo-aware base64 command" do
    assert HostKit.Runner.Files.read_file("/root/secret",
             runner: FakeRunner,
             sudo: true,
             test_pid: self()
           ) ==
             {:ok, "secret"}

    assert_receive {:cmd, "sh", ["-c", script], opts}
    assert script == "sudo base64 '/root/secret'"
    assert Keyword.get(opts, :stderr_to_stdout) == true
  end
end
