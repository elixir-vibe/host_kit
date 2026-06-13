defmodule HostKit.CLIRemoteIntegrationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @moduletag :integration

  @tag timeout: 300_000
  test "plans and applies a remote plan artifact over SSH" do
    if is_nil(System.find_executable("limactl")) do
      IO.puts("Skipping Lima CLI integration: limactl not available")
    else
      run_lima_cli_integration()
    end
  end

  defp run_lima_cli_integration do
    vm = System.get_env("HOSTKIT_LIMA_VM", "hostkit-test")
    ssh = lima_ssh_config(vm)
    unique = System.unique_integer([:positive])
    root = "/tmp/hostkit-cli-integration-#{unique}"
    mise_path = "#{root}/bin/mise"
    data_dir = "#{root}/share"
    config_path = Path.join(System.tmp_dir!(), "hostkit-cli-#{unique}.hostkit")
    plan_path = Path.join(System.tmp_dir!(), "hostkit-cli-#{unique}.plan.json")
    lock_path = Path.expand("../fixtures/package_locks/beam_apt.package.lock", __DIR__)

    cleanup(vm, root)

    on_exit(fn ->
      cleanup(vm, root)
      File.rm(config_path)
      File.rm(plan_path)
      Mix.Task.reenable("host_kit.plan")
      Mix.Task.reenable("host_kit.apply")
    end)

    File.write!(config_path, project_config(mise_path, data_dir))

    plan_args =
      ssh_args(ssh) ++
        [
          "--sudo",
          "--package-lock",
          lock_path,
          "--out",
          plan_path,
          config_path
        ]

    apply_args = ssh_args(ssh) ++ ["--sudo", "--plan", plan_path, "--confirm"]

    capture_io(fn -> Mix.Tasks.HostKit.Plan.run(plan_args) end)
    assert File.exists?(plan_path)

    capture_io(fn -> Mix.Tasks.HostKit.Apply.run(apply_args) end)
    assert {_, 0} = System.cmd("limactl", ["shell", vm, "--", "test", "-x", mise_path])
  end

  defp project_config(mise_path, data_dir) do
    """
    use HostKit.DSL

    project :cli_bootstrap do
      service :base do
        package :ca_certificates

        mise path: #{inspect(mise_path)}, system_data_dir: #{inspect(data_dir)}, packages: false do
        end
      end
    end
    """
  end

  defp ssh_args(ssh) do
    [
      "--remote",
      ssh.host,
      "--port",
      Integer.to_string(ssh.port),
      "--user",
      ssh.user,
      "--identity-file",
      ssh.identity_file,
      "--silently-accept-hosts"
    ]
  end

  defp lima_ssh_config(vm) do
    {config, 0} =
      System.cmd("limactl", ["show-ssh", "--format", "config", vm], stderr_to_stdout: true)

    %{
      host: field(config, "Hostname"),
      port: config |> field("Port") |> String.to_integer(),
      user: field(config, "User"),
      identity_file: field(config, "IdentityFile")
    }
  end

  defp field(config, name) do
    config
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case line |> String.trim() |> String.split(~r/\s+/, parts: 2) do
        [^name, value] -> String.trim(value, ~s("))
        _other -> nil
      end
    end)
  end

  defp cleanup(vm, path) do
    System.cmd("limactl", ["shell", vm, "--", "rm", "-rf", path], stderr_to_stdout: true)
    :ok
  end
end
