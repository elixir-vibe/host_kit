defmodule HostKit.Integration.InstanceCLITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @moduletag :integration

  setup do
    bin_dir =
      Path.join(System.tmp_dir!(), "hostkit-instance-cli-#{System.unique_integer([:positive])}")

    File.mkdir_p!(bin_dir)

    fake = Path.join(bin_dir, "incus")

    File.write!(fake, """
    #!/usr/bin/env sh
    set -eu
    log=\"$HOSTKIT_FAKE_INCUS_LOG\"
    printf '%s\\n' \"$*\" >> \"$log\"
    case \"$1\" in
      info) exit 1 ;;
      *) exit 0 ;;
    esac
    """)

    File.chmod!(fake, 0o755)
    log = Path.join(bin_dir, "incus.log")
    old_path = System.get_env("PATH", "")
    old_log = System.get_env("HOSTKIT_FAKE_INCUS_LOG")
    System.put_env("PATH", bin_dir <> ":" <> old_path)
    System.put_env("HOSTKIT_FAKE_INCUS_LOG", log)

    on_exit(fn ->
      System.put_env("PATH", old_path)
      restore_env("HOSTKIT_FAKE_INCUS_LOG", old_log)
      File.rm_rf!(bin_dir)
    end)

    %{log: log}
  end

  test "instance CLI ensure status and destroy delegate to declared backend", %{log: log} do
    Mix.Task.reenable("host_kit.instance")

    ensure_output =
      capture_io(fn ->
        Mix.Task.run("host_kit.instance", [
          "ensure",
          "hostkit_livebook_demo",
          "examples/livebook_demo_instance.exs"
        ])
      end)

    assert ensure_output =~ "ensured hostkit_livebook_demo backend=incus lifecycle=ephemeral"

    Mix.Task.reenable("host_kit.instance")

    status_output =
      capture_io(fn ->
        Mix.Task.run("host_kit.instance", [
          "status",
          "hostkit_livebook_demo",
          "examples/livebook_demo_instance.exs"
        ])
      end)

    assert status_output =~ "absent hostkit_livebook_demo backend=incus lifecycle=ephemeral"

    Mix.Task.reenable("host_kit.instance")

    destroy_output =
      capture_io(fn ->
        Mix.Task.run("host_kit.instance", [
          "destroy",
          "hostkit_livebook_demo",
          "examples/livebook_demo_instance.exs"
        ])
      end)

    assert destroy_output =~ "destroyed hostkit_livebook_demo backend=incus lifecycle=ephemeral"

    calls = File.read!(log)
    assert calls =~ "launch images:ubuntu/24.04 hostkit_livebook_demo"
    assert calls =~ "config device add hostkit_livebook_demo hostkit-ssh proxy"
    assert calls =~ "delete hostkit_livebook_demo --force"
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
