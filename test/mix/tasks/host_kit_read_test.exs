defmodule Mix.Tasks.HostKit.ReadTest do
  use HostKit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    Mix.Task.reenable("host_kit.read")
    :ok
  end

  test "prints current state presence" do
    dir = tmp_dir("host-kit-read-task")
    config = Path.join(dir, "config.exs")
    managed = Path.join(dir, "managed.txt")
    File.write!(managed, "current")
    File.write!(config, config_source(managed, "desired"))

    output = capture_io(fn -> Mix.Task.run("host_kit.read", ["--local", config]) end)

    assert output =~ "file.#{managed} present"
  after
    cleanup_tmp("host-kit-read-task")
  end

  defp config_source(path, content) do
    """
    use HostKit.DSL

    project :task_test do
      file #{inspect(path)}, content: #{inspect(content)}
    end
    """
  end

  defp tmp_dir(name) do
    path = Path.join(System.tmp_dir!(), name)
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp cleanup_tmp(name) do
    HostKit.SafeTmp.rm_rf!(Path.join(System.tmp_dir!(), name), "host-kit-")
  end
end
