defmodule HostKit.Instance.Backends.Incus do
  @moduledoc "Incus backend for lifecycle-managed HostKit instances."

  alias HostKit.Instance

  @behaviour HostKit.Instance.Backend

  @impl true
  def read(%Instance{} = instance, opts) do
    case cmd(["info", instance_name(instance)], opts) do
      {_output, 0} -> {:ok, %{instance | meta: Map.put(instance.meta, :present, true)}}
      {_output, _status} -> {:ok, nil}
    end
  end

  @impl true
  def apply(%Instance{} = instance, opts) do
    with :ok <- ensure_present(instance, opts),
         :ok <- ensure_exposed(instance, opts),
         :ok <- ensure_running(instance, opts),
         :ok <- wait_ready(instance, opts) do
      configure_nested_hosts(instance, opts)
    end
  end

  @impl true
  def delete(%Instance{} = instance, opts) do
    case cmd(["delete", instance_name(instance), "--force"], opts) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:incus_delete_failed, status, output}}
    end
  end

  defp ensure_present(instance, opts) do
    case read(instance, opts) do
      {:ok, %Instance{}} -> :ok
      {:ok, nil} -> launch(instance, opts)
    end
  end

  defp launch(%Instance{image: nil}, _opts), do: {:error, :missing_instance_image}

  defp launch(%Instance{} = instance, opts) do
    args =
      case instance.kind do
        :vm -> ["launch", instance.image, instance_name(instance), "--vm"]
        _kind -> ["launch", instance.image, instance_name(instance)]
      end

    case cmd(args, opts) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:incus_launch_failed, status, output}}
    end
  end

  defp ensure_exposed(%Instance{ports: ports} = instance, opts) do
    Enum.reduce_while(ports, :ok, fn port, :ok ->
      case ensure_port(instance, port, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp ensure_port(_instance, %{host: nil}, _opts), do: :ok

  defp ensure_port(
         instance,
         %{name: name, host: host, guest: guest, protocol: protocol} = port,
         opts
       ) do
    device = "hostkit-#{name}"
    bind = Map.get(port, :bind, "127.0.0.1")

    args = [
      "config",
      "device",
      "add",
      instance_name(instance),
      device,
      "proxy",
      "listen=#{protocol}:#{bind}:#{host}",
      "connect=#{protocol}:127.0.0.1:#{guest}"
    ]

    case cmd(args, opts) do
      {_output, 0} -> :ok
      {output, status} -> recover_device_add(instance, port, device, args, output, status, opts)
    end
  end

  defp recover_device_add(instance, port, device, add_args, output, status, opts) do
    cond do
      String.contains?(output, "already exists") ->
        replace_device(instance, device, add_args, opts)

      String.contains?(output, "address already in use") ->
        replace_legacy_device(instance, port, add_args, output, status, opts)

      true ->
        {:error, {:incus_device_add_failed, status, output}}
    end
  end

  defp replace_legacy_device(instance, port, add_args, output, status, opts) do
    case legacy_device(port) do
      nil ->
        {:error, {:incus_device_add_failed, status, output}}

      legacy ->
        remove_and_add_device(instance, legacy, add_args, opts)
    end
  end

  defp legacy_device(%{name: :ssh}), do: "sshproxy"
  defp legacy_device(%{name: :caddy_demo, host: host}), do: "web#{host}"
  defp legacy_device(%{name: :web, host: host}), do: "web#{host}"
  defp legacy_device(_port), do: nil

  defp replace_device(instance, device, add_args, opts),
    do: remove_and_add_device(instance, device, add_args, opts)

  defp remove_and_add_device(instance, device, add_args, opts) do
    with {_output, 0} <-
           cmd(["config", "device", "remove", instance_name(instance), device], opts),
         {_output, 0} <- cmd(add_args, opts) do
      :ok
    else
      {replace_output, replace_status} ->
        {:error, {:incus_device_replace_failed, replace_status, replace_output}}
    end
  end

  defp ensure_running(instance, opts) do
    case cmd(["start", instance_name(instance)], opts) do
      {_output, 0} -> :ok
      {output, status} -> maybe_already_running(output, status)
    end
  end

  defp wait_ready(instance, opts) do
    attempts = Keyword.get(opts, :incus_ready_attempts, 120)
    wait_ready(instance, opts, attempts)
  end

  defp wait_ready(_instance, _opts, 0), do: {:error, :incus_instance_not_ready}

  defp wait_ready(instance, opts, attempts) do
    case cmd(["exec", instance_name(instance), "--", "true"], opts) do
      {_output, 0} ->
        :ok

      {_output, _status} ->
        if Keyword.get(opts, :incus_no_sleep, false), do: :ok, else: Process.sleep(1_000)
        wait_ready(instance, opts, attempts - 1)
    end
  end

  defp configure_nested_hosts(%Instance{hosts: hosts} = instance, opts) do
    Enum.reduce_while(hosts, :ok, fn host, :ok ->
      case configure_host(instance, host, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp configure_host(instance, %{user: "root", meta: %{ssh: ssh}}, opts) do
    case Keyword.fetch(ssh, :password) do
      {:ok, password} -> configure_root_ssh(instance, password, opts)
      :error -> :ok
    end
  end

  defp configure_host(_instance, _host, _opts), do: :ok

  defp configure_root_ssh(instance, password, opts) do
    script = """
    set -eu
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y openssh-server sudo ca-certificates curl git
    printf 'root:%s\\n' #{shell_quote(password)} | chpasswd
    install -d -m 0755 /etc/ssh/sshd_config.d
    cat >/etc/ssh/sshd_config.d/99-hostkit-livebook-demo.conf <<'EOF'
    PermitRootLogin yes
    PasswordAuthentication yes
    KbdInteractiveAuthentication yes
    EOF
    systemctl restart ssh 2>/dev/null || service ssh restart
    """

    case cmd(["exec", instance_name(instance), "--", "sh", "-c", script], opts) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:incus_configure_ssh_failed, status, output}}
    end
  end

  defp shell_quote(value) do
    "'" <> String.replace(to_string(value), "'", "'\\''") <> "'"
  end

  defp maybe_already_running(output, _status) do
    if String.contains?(output, "already running") do
      :ok
    else
      {:error, {:incus_start_failed, output}}
    end
  end

  defp cmd(args, opts) do
    command = Keyword.get(opts, :incus, System.get_env("INCUS", "incus"))
    args = maybe_project(args, opts)

    case Keyword.get(opts, :incus_runner) do
      nil -> system_cmd(command, args, opts)
      runner when is_function(runner, 2) -> runner.(command, args)
    end
  end

  defp system_cmd(command, args, opts) do
    if Keyword.get(opts, :incus_sudo, incus_sudo_default()) do
      System.cmd("sudo", [command | args], stderr_to_stdout: true)
    else
      System.cmd(command, args, stderr_to_stdout: true)
    end
  end

  defp maybe_project(args, opts) do
    case Keyword.get(opts, :incus_project) do
      nil -> args
      project -> ["--project", to_string(project) | args]
    end
  end

  defp incus_sudo_default do
    System.get_env("HOSTKIT_INCUS_SUDO") in ["1", "true", "TRUE", "yes"]
  end

  defp instance_name(%Instance{name: name}), do: to_string(name)
end
