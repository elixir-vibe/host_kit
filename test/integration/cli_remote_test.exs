defmodule HostKit.CLIRemoteIntegrationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @moduletag :integration

  @tag timeout: 300_000
  test "plans and applies a remote plan artifact over SSH" do
    cond do
      System.find_executable("limactl") ->
        run_lima_cli_integration()

      System.find_executable("incus") && System.get_env("HOSTKIT_INCUS_INTEGRATION") == "1" ->
        run_incus_cli_integration()

      true ->
        IO.puts(
          "Skipping remote CLI integration: limactl unavailable and HOSTKIT_INCUS_INTEGRATION is not 1"
        )
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

  defp run_incus_cli_integration do
    script = Path.expand("../../scripts/incus_integration_vm.sh", __DIR__)
    unique = System.unique_integer([:positive])
    root = "/tmp/hostkit-cli-integration-#{unique}"
    mise_path = "#{root}/bin/mise"
    data_dir = "#{root}/share"
    config_path = Path.join(System.tmp_dir!(), "hostkit-cli-#{unique}.hostkit")
    plan_path = Path.join(System.tmp_dir!(), "hostkit-cli-#{unique}.plan.json")
    lock_path = Path.expand("../fixtures/package_locks/beam_apt.package.lock", __DIR__)
    env = incus_env()

    assert {_, 0} = System.cmd(script, ["create"], env: env, stderr_to_stdout: true)
    {ip, 0} = System.cmd(script, ["ip"], env: env, stderr_to_stdout: true)
    ip = String.trim(ip)

    on_exit(fn ->
      ssh_rm_rf(ip, root)
      File.rm(config_path)
      File.rm(plan_path)
      Mix.Task.reenable("host_kit.plan")
      Mix.Task.reenable("host_kit.apply")
    end)

    File.write!(config_path, project_config(mise_path, data_dir))

    plan_args =
      [
        "--remote",
        ip,
        "--user",
        "root",
        "--identity-file",
        System.get_env("HOSTKIT_SSH_IDENTITY_FILE", Path.expand("~/.ssh/id_ed25519")),
        "--silently-accept-hosts",
        "--sudo",
        "--package-lock",
        lock_path,
        "--out",
        plan_path,
        config_path
      ]

    apply_args = [
      "--remote",
      ip,
      "--user",
      "root",
      "--identity-file",
      System.get_env("HOSTKIT_SSH_IDENTITY_FILE", Path.expand("~/.ssh/id_ed25519")),
      "--silently-accept-hosts",
      "--sudo",
      "--plan",
      plan_path,
      "--confirm"
    ]

    capture_io(fn -> Mix.Tasks.HostKit.Plan.run(plan_args) end)
    assert File.exists?(plan_path)

    capture_io(fn -> Mix.Tasks.HostKit.Apply.run(apply_args) end)
    assert {_, 0} = ssh(ip, ["test", "-x", mise_path])
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

  defp incus_env do
    env = []
    env = put_env(env, "INCUS", System.get_env("INCUS"))
    env = put_env(env, "HOSTKIT_INCUS_VM", System.get_env("HOSTKIT_INCUS_VM"))
    env = put_env(env, "HOSTKIT_INCUS_SUDO", System.get_env("HOSTKIT_INCUS_SUDO"))
    env = put_env(env, "HOSTKIT_INCUS_IMAGE", System.get_env("HOSTKIT_INCUS_IMAGE"))
    env = put_env(env, "HOSTKIT_INCUS_TYPE", System.get_env("HOSTKIT_INCUS_TYPE"))

    put_env(
      env,
      "HOSTKIT_SSH_PUBLIC_KEY",
      System.get_env("HOSTKIT_SSH_PUBLIC_KEY", Path.expand("~/.ssh/id_ed25519.pub"))
    )
  end

  defp put_env(env, _key, nil), do: env
  defp put_env(env, key, value), do: [{key, value} | env]

  defp ssh_rm_rf(host, path) do
    ssh(host, ["rm", "-rf", path])
    :ok
  end

  defp ssh(host, remote_args) do
    System.cmd(
      "ssh",
      [
        "-i",
        System.get_env("HOSTKIT_SSH_IDENTITY_FILE", Path.expand("~/.ssh/id_ed25519")),
        "-o",
        "StrictHostKeyChecking=accept-new",
        "root@#{host}"
        | remote_args
      ],
      stderr_to_stdout: true
    )
  end
end
