defmodule HostKit.IntegrationTarget do
  @moduledoc false

  defstruct [:host, :cleanup, :verify]

  def selected do
    case System.get_env("HOSTKIT_INTEGRATION_TOOL", "auto") do
      "auto" -> auto()
      "incus" -> incus()
      "lima" -> lima()
      "remote" -> configured()
      tool -> {:skip, "unknown HOSTKIT_INTEGRATION_TOOL=#{inspect(tool)}"}
    end
  end

  defp auto do
    cond do
      System.find_executable("limactl") ->
        lima()

      System.find_executable("incus") && System.get_env("HOSTKIT_INCUS_INTEGRATION") == "1" ->
        incus()

      true ->
        {:skip, "no integration tool selected"}
    end
  end

  defp configured do
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

  defp lima do
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

  defp incus do
    if System.find_executable("incus") do
      script = Path.expand("../../../scripts/incus_integration_vm.sh", __DIR__)
      env = incus_env()

      timed("incus create", fn -> assert_cmd!(script, ["create"], env: env) end)

      {ip, 0} =
        timed("incus ip", fn -> System.cmd(script, ["ip"], env: env, stderr_to_stdout: true) end)

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

  defp target(host, cleanup, verify),
    do: %__MODULE__{host: host, cleanup: cleanup, verify: verify}

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
    []
    |> put_env("INCUS", System.get_env("INCUS"))
    |> put_env("HOSTKIT_INCUS_INSTANCE", System.get_env("HOSTKIT_INCUS_INSTANCE"))
    |> put_env("HOSTKIT_INCUS_VM", System.get_env("HOSTKIT_INCUS_VM"))
    |> put_env("HOSTKIT_INCUS_SUDO", System.get_env("HOSTKIT_INCUS_SUDO") || incus_sudo_default())
    |> put_env("HOSTKIT_INCUS_IMAGE", System.get_env("HOSTKIT_INCUS_IMAGE"))
    |> put_env("HOSTKIT_INCUS_TYPE", System.get_env("HOSTKIT_INCUS_TYPE"))
    |> put_env(
      "HOSTKIT_SSH_PUBLIC_KEY",
      System.get_env("HOSTKIT_SSH_PUBLIC_KEY", Path.expand("~/.ssh/id_ed25519.pub"))
    )
  end

  defp incus_sudo_default do
    incus = System.get_env("INCUS", "incus")

    case System.cmd(incus, ["list"], stderr_to_stdout: true) do
      {_output, 0} -> "false"
      {_output, _status} -> if sudo_without_password?(), do: "true", else: "false"
    end
  rescue
    ErlangError -> "false"
  end

  defp sudo_without_password? do
    match?({_output, 0}, System.cmd("sudo", ["-n", "true"], stderr_to_stdout: true))
  rescue
    ErlangError -> false
  end

  defp put_env(env, _key, nil), do: env
  defp put_env(env, key, value), do: [{key, value} | env]

  defp remote_rm_rf(host, path) do
    remote_cmd(host, "rm", ["-rf", path])
    :ok
  end

  defp remote_test(host, path), do: remote_cmd(host, "test", ["-x", path])

  defp remote_cmd(host, command, args) do
    {:ok, conn} = HostKit.Runner.SSH.Connection.open(HostKit.Host.ssh_options(host))

    try do
      HostKit.Runner.SSH.Connection.cmd(command, args, conn: conn)
    after
      HostKit.Runner.SSH.Connection.close(conn)
    end
  end

  defp timed(label, fun) do
    started = System.monotonic_time(:millisecond)
    IO.puts("[hostkit:integration-target] start #{label}")

    try do
      fun.()
    after
      duration = System.monotonic_time(:millisecond) - started
      IO.puts("[hostkit:integration-target] finish #{label} #{duration}ms")
    end
  end

  defp assert_cmd!(command, args, opts) do
    IO.puts("[hostkit:integration-target] exec #{command} #{Enum.join(args, " ")}")

    env =
      opts
      |> Keyword.get(:env, [])
      |> Enum.map(fn {key, value} -> {to_charlist(key), to_charlist(value)} end)

    port_opts = [:binary, :exit_status, :stderr_to_stdout, args: args]
    port_opts = if env == [], do: port_opts, else: [{:env, env} | port_opts]
    port = Port.open({:spawn_executable, command}, port_opts)

    case collect_port(port, []) do
      {0, _output} ->
        :ok

      {status, output} ->
        raise "command failed #{command}: #{status}\n#{IO.iodata_to_binary(Enum.reverse(output))}"
    end
  end

  defp collect_port(port, output) do
    receive do
      {^port, {:data, data}} ->
        IO.write(data)
        collect_port(port, [data | output])

      {^port, {:exit_status, status}} ->
        {status, output}
    end
  end
end
