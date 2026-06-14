defmodule Mix.Tasks.HostKitInstanceTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    Mix.Task.reenable("host_kit.instance")
    :ok
  end

  test "status reads a declared instance through its backend" do
    output =
      with_env("INCUS", "false", fn ->
        capture_io(fn ->
          Mix.Task.run("host_kit.instance", [
            "status",
            "hostkit_livebook_demo",
            "examples/livebook_demo_instance.exs"
          ])
        end)
      end)

    assert output =~ "absent hostkit_livebook_demo backend=incus lifecycle=ephemeral"
  end

  test "unknown instance returns a clear error" do
    assert_raise Mix.Error, ~r/instance "missing" is not declared/, fn ->
      Mix.Task.run("host_kit.instance", [
        "status",
        "missing",
        "examples/livebook_demo_instance.exs"
      ])
    end
  end

  defp with_env(name, value, fun) do
    old = System.get_env(name)
    System.put_env(name, value)

    try do
      fun.()
    after
      restore_env(name, old)
    end
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
