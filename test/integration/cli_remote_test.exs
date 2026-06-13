defmodule HostKit.CLIRemoteIntegrationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @moduletag :integration

  @tag timeout: 300_000
  test "plans and applies a remote plan artifact over SSH" do
    case integration_target() do
      {:ok, target} ->
        run_remote_cli_integration(target)

      {:skip, reason} ->
        IO.puts("Skipping remote CLI integration: #{reason}")
    end
  end

  defp integration_target do
    case System.get_env("HOSTKIT_INTEGRATION_TOOL", "auto") do
      "auto" -> auto_target()
      "incus" -> incus_target()
      "lima" -> lima_target()
      "remote" -> configured_target()
      tool -> {:skip, "unknown HOSTKIT_INTEGRATION_TOOL=#{inspect(tool)}"}
    end
  end

  defp auto_target do
    cond do
      System.find_executable("limactl") ->
        lima_target()

      System.find_executable("incus") && System.get_env("HOSTKIT_INCUS_INTEGRATION") == "1" ->
        incus_target()

      true ->
        {:skip, "no integration tool selected"}
    end
  end

  defp configured_target do
    config_path = System.get_env("HOSTKIT_INTEGRATION_CONFIG")
    host_name = System.get_env("HOSTKIT_INTEGRATION_HOST", "integration")

    if config_path do
      project = HostKit.load!(config_path)
      host = fetch_host!(project, host_name)
      {:ok, target(host, &remote_rm_rf(host, &1), &remote_test(host, &1))}
    else
      {:skip, "HOSTKIT_INTEGRATION_CONFIG is required for HOSTKIT_INTEGRATION_TOOL=remote"}
    end
  end

  defp lima_target do
    if System.find_executable("limactl") do
      vm = System.get_env("HOSTKIT_LIMA_VM", "hostkit-test")
      host = lima_host(vm)

      {:ok,
       target(
         host,
         fn path ->
           System.cmd("limactl", ["shell", vm, "--", "rm", "-rf", path], stderr_to_stdout: true)
           :ok
         end,
         fn path -> System.cmd("limactl", ["shell", vm, "--", "test", "-x", path]) end
       )}
    else
      {:skip, "limactl unavailable"}
    end
  end

  defp incus_target do
    if System.find_executable("incus") do
      script = Path.expand("../../scripts/incus_integration_vm.sh", __DIR__)
      env = incus_env()

      assert {_, 0} = System.cmd(script, ["create"], env: env, stderr_to_stdout: true)
      {ip, 0} = System.cmd(script, ["ip"], env: env, stderr_to_stdout: true)

      host = %HostKit.Host{
        name: :integration,
        hostname: String.trim(ip),
        user: "root",
        sudo: true,
        meta: %{
          ssh: [
            identity_file:
              System.get_env("HOSTKIT_SSH_IDENTITY_FILE", Path.expand("~/.ssh/id_ed25519")),
            silently_accept_hosts: true
          ]
        }
      }

      {:ok, target(host, &remote_rm_rf(host, &1), &remote_test(host, &1))}
    else
      {:skip, "incus unavailable"}
    end
  end

  defp target(host, cleanup, verify), do: %{host: host, cleanup: cleanup, verify: verify}

  defp run_remote_cli_integration(%{host: host, cleanup: cleanup, verify: verify}) do
    unique = System.unique_integer([:positive])
    root = "/tmp/hostkit-cli-integration-#{unique}"
    mise_path = "#{root}/bin/mise"
    data_dir = "#{root}/share"
    config_path = Path.join(System.tmp_dir!(), "hostkit-cli-#{unique}.exs")
    plan_path = Path.join(System.tmp_dir!(), "hostkit-cli-#{unique}.plan.json")
    lock_path = Path.expand("../fixtures/package_locks/beam_apt.package.lock", __DIR__)

    cleanup.(root)

    on_exit(fn ->
      cleanup.(root)
      File.rm(config_path)
      File.rm(plan_path)
      Mix.Task.reenable("host_kit.plan")
      Mix.Task.reenable("host_kit.apply")
    end)

    File.write!(config_path, project_source(host, mise_path, data_dir))

    plan_args = [
      "--host",
      to_string(host.name),
      "--package-lock",
      lock_path,
      "--out",
      plan_path,
      config_path
    ]

    apply_args = ["--host", to_string(host.name), "--plan", plan_path, "--confirm", config_path]

    capture_io(fn -> Mix.Tasks.HostKit.Plan.run(plan_args) end)
    assert File.exists?(plan_path)

    capture_io(fn -> Mix.Tasks.HostKit.Apply.run(apply_args) end)
    assert {_, 0} = verify.(mise_path)
  end

  defp project_source(host, mise_path, data_dir) do
    host_name = host.name
    hostname = host.hostname
    user = host.user
    sudo = host.sudo
    ssh_opts = host.meta[:ssh] || []

    quote do
      use HostKit.DSL

      project :cli_bootstrap do
        host unquote(host_name) do
          hostname(unquote(hostname))
          user(unquote(user))
          sudo(unquote(sudo))
          ssh(unquote(ssh_opts))
        end

        service :base do
          package(:ca_certificates)

          mise path: unquote(mise_path), system_data_dir: unquote(data_dir), packages: false do
          end
        end
      end
    end
    |> Macro.to_string()
    |> Kernel.<>("\n")
  end

  defp fetch_host!(project, name) do
    case HostKit.Project.fetch_host(project, name) do
      {:ok, host} -> host
      :error -> raise "host #{inspect(name)} not found in #{inspect(project.name)}"
    end
  end

  defp lima_host(vm) do
    {config, 0} =
      System.cmd("limactl", ["show-ssh", "--format", "config", vm], stderr_to_stdout: true)

    %HostKit.Host{
      name: :integration,
      hostname: field(config, "Hostname"),
      user: field(config, "User"),
      sudo: true,
      meta: %{
        ssh: [
          port: config |> field("Port") |> String.to_integer(),
          identity_file: field(config, "IdentityFile"),
          silently_accept_hosts: true
        ]
      }
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

  defp remote_rm_rf(host, path) do
    remote_cmd(host, "rm", ["-rf", path])
    :ok
  end

  defp remote_test(host, path), do: remote_cmd(host, "test", ["-x", path])

  defp remote_cmd(host, command, args) do
    {:ok, conn} = HostKit.Runner.SSH.Connection.open(ssh_opts(host))

    try do
      HostKit.Runner.SSH.Connection.cmd(command, args, conn: conn)
    after
      HostKit.Runner.SSH.Connection.close(conn)
    end
  end

  defp ssh_opts(host), do: HostKit.Host.ssh_options(host)
end
