defmodule HostKit.Scripts.LivebookDemoVMScriptTest do
  use ExUnit.Case, async: true

  test "status reports absent target through HostKit instance backend" do
    env = [
      {"INCUS", "false"},
      {"HOSTKIT_INCUS_SUDO", "false"},
      {"MIX_ENV", "test"}
    ]

    {output, status} =
      System.cmd("mix", ["run", "scripts/livebook_demo_vm.exs", "--", "status"],
        env: env,
        stderr_to_stdout: true
      )

    assert status == 0
    assert output =~ "hostkit-livebook-demo is absent"
  end
end
