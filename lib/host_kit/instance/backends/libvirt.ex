defmodule HostKit.Instance.Backends.Libvirt do
  @moduledoc """
  Libvirt backend for lifecycle-managed HostKit instances.

  This backend intentionally uses libvirt's stable command-line tools instead
  of BEAM-native libvirt bindings. HostKit keeps the user-facing DSL generic;
  backend options configure the local libvirt command boundary.
  """

  alias HostKit.Instance

  @behaviour HostKit.Instance.Backend

  @impl true
  def read(%Instance{} = instance, opts) do
    opts = backend_opts(instance, opts)

    case virsh(["dominfo", instance_name(instance)], opts) do
      {_output, 0} ->
        {:ok, %{instance | meta: Map.put(instance.meta, :present, true)}}

      {"HOSTKIT_LIBVIRT_EXEC_ERROR:" <> reason, _status} ->
        {:error, {:libvirt_command_failed, String.trim(reason)}}

      {_output, _status} ->
        {:ok, nil}
    end
  end

  @impl true
  def apply(%Instance{} = instance, opts) do
    opts = backend_opts(instance, opts)

    with :ok <- validate(instance),
         :ok <- ensure_disk(instance, opts),
         {:ok, seed_image} <- ensure_seed(instance, opts),
         :ok <- ensure_defined(instance, seed_image, opts),
         :ok <- ensure_running(instance, opts),
         :ok <- wait_ready(instance, opts) do
      :ok
    end
  end

  @impl true
  def delete(%Instance{} = instance, opts) do
    opts = backend_opts(instance, opts)

    with :ok <- destroy(instance, opts),
         :ok <- undefine(instance, opts) do
      :ok
    end
  end

  defp validate(%Instance{kind: kind}) when kind not in [nil, :vm],
    do: {:error, {:unsupported_libvirt_instance_kind, kind}}

  defp validate(%Instance{backend_config: config}) do
    if config[:disk] || config[:volume] do
      :ok
    else
      {:error, :missing_libvirt_disk}
    end
  end

  defp ensure_disk(%Instance{backend_config: config}, opts) do
    case {config[:base_image], config[:disk]} do
      {nil, _disk} ->
        :ok

      {_base_image, nil} ->
        {:error, :missing_libvirt_disk}

      {base_image, disk} ->
        case qemu_img(["info", disk], opts) do
          {_output, 0} ->
            :ok

          {_output, _status} ->
            size = to_string(Map.get(config, :disk_size, "20G"))

            qemu_img(
              ["create", "-f", "qcow2", "-F", "qcow2", "-b", base_image, disk, size],
              opts
            )
            |> expect_ok(:libvirt_disk_create_failed)
        end
    end
  end

  defp ensure_seed(%Instance{backend_config: config}, opts) do
    case {config[:seed_image], config[:user_data], config[:meta_data]} do
      {nil, nil, nil} ->
        {:ok, nil}

      {nil, _user_data, _meta_data} ->
        {:error, :missing_libvirt_seed_image}

      {seed_image, user_data, meta_data} ->
        with {:ok, user_data_path} <- write_temp("user-data", user_data || default_user_data()),
             {:ok, meta_data_path} <-
               write_temp("meta-data", meta_data || default_meta_data(config)),
             :ok <-
               cloud_localds([seed_image, user_data_path, meta_data_path], opts)
               |> expect_ok(:libvirt_seed_create_failed) do
          {:ok, seed_image}
        end
    end
  end

  defp ensure_defined(instance, seed_image, opts) do
    case read(instance, opts) do
      {:ok, %Instance{}} ->
        :ok

      {:ok, nil} ->
        define(instance, seed_image, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp define(instance, seed_image, opts) do
    emit(opts, :instance_define_started, instance)

    with {:ok, xml_path} <-
           write_temp("#{instance_name(instance)}.xml", domain_xml(instance, seed_image)),
         :ok <- virsh(["define", xml_path], opts) |> expect_ok(:libvirt_define_failed) do
      emit(opts, :instance_define_finished, instance)
      :ok
    end
  end

  defp ensure_running(instance, opts) do
    emit(opts, :instance_start_started, instance)

    case virsh(["start", instance_name(instance)], opts) do
      {_output, 0} ->
        emit(opts, :instance_start_finished, instance)
        :ok

      {output, status} ->
        if already_active?(output) do
          emit(opts, :instance_start_finished, instance)
          :ok
        else
          {:error, {:libvirt_start_failed, status, output}}
        end
    end
  end

  defp wait_ready(instance, opts) do
    attempts = Keyword.get(opts, :libvirt_ready_attempts, 60)
    emit(opts, :instance_ready_waiting, instance, %{attempts: attempts})
    wait_ready(instance, opts, attempts)
  end

  defp wait_ready(_instance, _opts, 0), do: {:error, :libvirt_instance_not_ready}

  defp wait_ready(instance, opts, attempts) do
    case virsh(["domstate", instance_name(instance)], opts) do
      {output, 0} ->
        if String.trim(output) == "running" do
          emit(opts, :instance_ready_passed, instance)
          :ok
        else
          sleep(opts)
          wait_ready(instance, opts, attempts - 1)
        end

      {_output, _status} ->
        sleep(opts)
        wait_ready(instance, opts, attempts - 1)
    end
  end

  defp destroy(instance, opts) do
    case virsh(["destroy", instance_name(instance)], opts) do
      {_output, 0} ->
        :ok

      {output, _status} ->
        if not_running?(output), do: :ok, else: {:error, {:libvirt_destroy_failed, output}}
    end
  end

  defp undefine(%Instance{backend_config: config} = instance, opts) do
    args = ["undefine", instance_name(instance)] ++ undefine_flags(config)

    case virsh(args, opts) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:libvirt_undefine_failed, status, output}}
    end
  end

  defp undefine_flags(config) do
    flags = []

    flags =
      if Map.get(config, :remove_storage, false),
        do: ["--remove-all-storage" | flags],
        else: flags

    flags = if Map.get(config, :remove_nvram, true), do: ["--nvram" | flags], else: flags
    Enum.reverse(flags)
  end

  defp domain_xml(%Instance{backend_config: config} = instance, seed_image) do
    disk = config[:disk] || config[:volume]

    memory_mb = Map.get(config, :memory_mb, 2_048)
    vcpus = Map.get(config, :vcpus, 1)
    network = Map.get(config, :network, "default")

    """
    <domain type='kvm'>
      <name>#{xml_escape(instance_name(instance))}</name>
      <memory unit='MiB'>#{memory_mb}</memory>
      <vcpu>#{vcpus}</vcpu>
      <os>
        <type arch='x86_64' machine='q35'>hvm</type>
        <boot dev='hd'/>
      </os>
      <features>
        <acpi/>
        <apic/>
      </features>
      <devices>
        <disk type='file' device='disk'>
          <driver name='qemu' type='qcow2'/>
          <source file='#{xml_escape(disk)}'/>
          <target dev='vda' bus='virtio'/>
        </disk>
        #{seed_disk_xml(seed_image)}
        <interface type='network'>
          <source network='#{xml_escape(network)}'/>
          #{mac_xml(config[:mac])}
          <model type='virtio'/>
        </interface>
        <serial type='pty'/>
        <console type='pty'>
          <target type='serial' port='0'/>
        </console>
        <graphics type='none'/>
      </devices>
    </domain>
    """
  end

  defp seed_disk_xml(nil), do: ""

  defp seed_disk_xml(seed_image) do
    """
        <disk type='file' device='cdrom'>
          <driver name='qemu' type='raw'/>
          <source file='#{xml_escape(seed_image)}'/>
          <target dev='sda' bus='sata'/>
          <readonly/>
        </disk>
    """
  end

  defp mac_xml(nil), do: ""
  defp mac_xml(mac), do: "<mac address='#{xml_escape(mac)}'/>"

  defp default_user_data do
    """
    #cloud-config
    package_update: true
    packages:
      - openssh-server
      - sudo
      - ca-certificates
      - curl
      - git
    """
  end

  defp default_meta_data(config) do
    name = Map.get(config, :hostname, "hostkit-libvirt")

    """
    instance-id: #{name}
    local-hostname: #{name}
    """
  end

  defp write_temp(name, content) when is_binary(content) do
    dir = Path.join(System.tmp_dir!(), "hostkit-libvirt")
    path = Path.join(dir, "#{System.unique_integer([:positive])}-#{name}")

    with :ok <- File.mkdir_p(dir), :ok <- File.write(path, content) do
      {:ok, path}
    end
  end

  defp virsh(args, opts), do: cmd(:virsh, args, opts)
  defp qemu_img(args, opts), do: cmd(:qemu_img, args, opts)
  defp cloud_localds(args, opts), do: cmd(:cloud_localds, args, opts)

  defp cmd(kind, args, opts) do
    command = Keyword.fetch!(opts, kind)

    case Keyword.get(opts, :libvirt_runner) do
      nil -> system_cmd(command, args, opts)
      runner when is_function(runner, 3) -> runner.(kind, command, args)
      runner when is_function(runner, 2) -> runner.(command, args)
    end
  end

  defp system_cmd(command, args, opts) do
    if Keyword.get(opts, :libvirt_sudo, libvirt_sudo_default()) do
      System.cmd("sudo", [command | args], stderr_to_stdout: true)
    else
      System.cmd(command, args, stderr_to_stdout: true)
    end
  rescue
    error in ErlangError ->
      {"HOSTKIT_LIBVIRT_EXEC_ERROR: #{Exception.message(error)}", 127}
  end

  defp backend_opts(%Instance{backend_config: config}, opts) do
    opts
    |> put_config(:virsh, config[:virsh] || config[:command] || System.get_env("VIRSH", "virsh"))
    |> put_config(:qemu_img, config[:qemu_img] || System.get_env("QEMU_IMG", "qemu-img"))
    |> put_config(
      :cloud_localds,
      config[:cloud_localds] || System.get_env("CLOUD_LOCALDS", "cloud-localds")
    )
    |> put_config(:libvirt_sudo, config[:sudo])
  end

  defp put_config(opts, _key, nil), do: opts
  defp put_config(opts, key, value), do: Keyword.put(opts, key, value)

  defp expect_ok({_output, 0}, _reason), do: :ok
  defp expect_ok({output, status}, reason), do: {:error, {reason, status, output}}

  defp already_active?(output), do: String.contains?(output, "already active")

  defp not_running?(output),
    do: String.contains?(output, "not running") or String.contains?(output, "not active")

  defp sleep(opts) do
    unless Keyword.get(opts, :libvirt_no_sleep, false), do: Process.sleep(1_000)
  end

  defp emit(opts, type, instance, details \\ %{}) do
    HostKit.Apply.Events.emit(opts, type,
      resource_id: Instance.id(instance),
      details: Map.put(details, :backend, :libvirt)
    )
  end

  defp libvirt_sudo_default do
    System.get_env("HOSTKIT_LIBVIRT_SUDO") in ["1", "true", "TRUE", "yes"]
  end

  defp instance_name(%Instance{name: name}), do: to_string(name)

  defp xml_escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
