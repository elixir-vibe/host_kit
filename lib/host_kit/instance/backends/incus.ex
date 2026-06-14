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
         :ok <- ensure_exposed(instance, opts) do
      ensure_running(instance, opts)
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

  defp ensure_port(instance, %{name: name, host: host, guest: guest, protocol: protocol}, opts) do
    device = "hostkit-#{name}"

    args = [
      "config",
      "device",
      "add",
      instance_name(instance),
      device,
      "proxy",
      "listen=#{protocol}:0.0.0.0:#{host}",
      "connect=#{protocol}:127.0.0.1:#{guest}"
    ]

    case cmd(args, opts) do
      {_output, 0} ->
        :ok

      {output, status} ->
        maybe_replace_existing_device(instance, device, args, output, status, opts)
    end
  end

  defp maybe_replace_existing_device(instance, device, add_args, output, _status, opts) do
    if String.contains?(output, "already exists") do
      with {_output, 0} <-
             cmd(["config", "device", "remove", instance_name(instance), device], opts),
           {_output, 0} <- cmd(add_args, opts) do
        :ok
      else
        {replace_output, replace_status} ->
          {:error, {:incus_device_replace_failed, replace_status, replace_output}}
      end
    else
      {:error, {:incus_device_add_failed, output}}
    end
  end

  defp ensure_running(instance, opts) do
    case cmd(["start", instance_name(instance)], opts) do
      {_output, 0} -> :ok
      {output, status} -> maybe_already_running(output, status)
    end
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
