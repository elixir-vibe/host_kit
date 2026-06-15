defmodule Mix.Tasks.HostKit.ReadAuditFactsTest do
  use HostKit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    Mix.Task.reenable("host_kit.read")
    Mix.Task.reenable("host_kit.audit")
    Mix.Task.reenable("host_kit.facts")
    :ok
  end

  test "read prints current state presence" do
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

  test "audit prints compact report plus plan" do
    dir = tmp_dir("host-kit-audit-task")
    config = Path.join(dir, "config.exs")
    managed = Path.join(dir, "managed.txt")
    File.write!(managed, "current")
    File.write!(config, config_source(managed, "desired"))

    output = capture_io(fn -> Mix.Task.run("host_kit.audit", ["--local", config]) end)

    assert output =~ "Audit: 1 managed resources, 1 drift"
    assert output =~ "Plan: 0 to create, 1 to update"
  after
    cleanup_tmp("host-kit-audit-task")
  end

  test "facts prints selected local facts as json" do
    output =
      capture_io(fn ->
        Mix.Task.run("host_kit.facts", ["--local", "--only", "os", "--format", "json"])
      end)

    assert {:ok, decoded} = Jason.decode(output)
    assert Map.has_key?(decoded, "os")
    refute Map.has_key?(decoded, "users")
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
