defmodule HostKit.Instance.LibvirtBackendTest do
  use ExUnit.Case, async: true

  alias HostKit.Instance
  alias HostKit.Instance.Backends.Libvirt

  test "read reports missing virsh command as an error" do
    instance = Instance.new(:demo, backend: :libvirt)

    assert {:error, {:libvirt_command_failed, reason}} =
             Libvirt.read(instance, virsh: "/definitely/missing/virsh")

    assert reason =~ ":enoent"
  end

  test "read returns nil when domain is missing" do
    runner = fn :virsh, _command, ["dominfo", "demo"] -> {"failed to get domain", 1} end
    instance = Instance.new(:demo, backend: :libvirt)

    assert {:ok, nil} = Libvirt.read(instance, libvirt_runner: runner)
  end

  test "apply creates disk defines domain starts and waits for running state" do
    parent = self()

    runner = fn kind, command, args ->
      send(parent, {kind, command, args})

      case {kind, args} do
        {:qemu_img, ["info", "/var/lib/libvirt/images/demo.qcow2"]} ->
          {"missing", 1}

        {:virsh, ["dominfo", "demo"]} ->
          {"missing", 1}

        {:virsh, ["domstate", "demo"]} ->
          {"running\n", 0}

        {:virsh, ["define", xml_path]} ->
          send(parent, {:xml_content, File.read!(xml_path)})
          {"", 0}

        {_kind, _args} ->
          {"", 0}
      end
    end

    instance =
      Instance.new(:demo,
        backend: :libvirt,
        kind: :vm,
        backend_config: [
          disk: "/var/lib/libvirt/images/demo.qcow2",
          base_image: "/var/lib/libvirt/images/debian-12-base.qcow2",
          disk_size: "40G",
          memory_mb: 4096,
          vcpus: 2,
          network: "default",
          mac: "52:54:00:12:34:56",
          sudo: false
        ]
      )

    assert :ok = Libvirt.apply(instance, libvirt_runner: runner, libvirt_no_sleep: true)

    assert_received {:qemu_img, "qemu-img", ["info", "/var/lib/libvirt/images/demo.qcow2"]}

    assert_received {:qemu_img, "qemu-img",
                     [
                       "create",
                       "-f",
                       "qcow2",
                       "-F",
                       "qcow2",
                       "-b",
                       "/var/lib/libvirt/images/debian-12-base.qcow2",
                       "/var/lib/libvirt/images/demo.qcow2",
                       "40G"
                     ]}

    assert_received {:virsh, "virsh", ["define", xml_path]}
    assert_received {:xml_content, xml}
    assert xml =~ "<name>demo</name>"
    assert xml =~ "<memory unit='MiB'>4096</memory>"
    assert xml =~ "<vcpu>2</vcpu>"
    assert xml =~ "<source file='/var/lib/libvirt/images/demo.qcow2'/>"
    assert xml =~ "<source network='default'/>"
    assert xml =~ "<mac address='52:54:00:12:34:56'/>"
    refute File.exists?(xml_path)

    assert_received {:virsh, "virsh", ["start", "demo"]}
    assert_received {:virsh, "virsh", ["domstate", "demo"]}
  end

  test "apply can create a cloud-init seed image" do
    parent = self()

    runner = fn kind, command, args ->
      send(parent, {kind, command, args})

      case {kind, args} do
        {:virsh, ["dominfo", "demo"]} ->
          {"missing", 1}

        {:virsh, ["domstate", "demo"]} ->
          {"running\n", 0}

        {:cloud_localds, [_seed, user_data_path, meta_data_path]} ->
          send(parent, {:seed_content, File.read!(user_data_path), File.read!(meta_data_path)})
          {"", 0}

        {:virsh, ["define", xml_path]} ->
          send(parent, {:xml_content, File.read!(xml_path)})
          {"", 0}

        {_kind, _args} ->
          {"", 0}
      end
    end

    instance =
      Instance.new(:demo,
        backend: :libvirt,
        backend_config: [
          disk: "/var/lib/libvirt/images/demo.qcow2",
          seed_image: "/var/lib/libvirt/images/demo-seed.iso",
          user_data: "#cloud-config\npackages: [openssh-server]\n",
          meta_data: "instance-id: demo\nlocal-hostname: demo\n"
        ]
      )

    assert :ok = Libvirt.apply(instance, libvirt_runner: runner, libvirt_no_sleep: true)

    assert_received {:cloud_localds, "cloud-localds",
                     ["/var/lib/libvirt/images/demo-seed.iso", user_data_path, meta_data_path]}

    assert_received {:seed_content, user_data, meta_data}
    assert user_data =~ "#cloud-config"
    assert meta_data =~ "instance-id: demo"
    refute File.exists?(user_data_path)
    refute File.exists?(meta_data_path)

    assert_received {:virsh, "virsh", ["define", xml_path]}
    assert_received {:xml_content, xml}
    assert xml =~ "<source file='/var/lib/libvirt/images/demo-seed.iso'/>"
    refute File.exists?(xml_path)
  end

  test "apply rejects non-VM instance kinds" do
    instance = Instance.new(:demo, backend: :libvirt, kind: :container)

    assert {:error, {:unsupported_libvirt_instance_kind, :container}} =
             Libvirt.apply(instance, [])
  end

  test "apply requires a disk or volume" do
    instance = Instance.new(:demo, backend: :libvirt, kind: :vm)

    assert {:error, :missing_libvirt_disk} = Libvirt.apply(instance, [])
  end

  test "delete destroys and undefines domain without removing storage by default" do
    parent = self()

    runner = fn kind, command, args ->
      send(parent, {kind, command, args})
      {"", 0}
    end

    instance = Instance.new(:demo, backend: :libvirt)

    assert :ok = Libvirt.delete(instance, libvirt_runner: runner)

    assert_received {:virsh, "virsh", ["destroy", "demo"]}
    assert_received {:virsh, "virsh", ["undefine", "demo", "--nvram"]}
  end

  test "delete can remove libvirt-managed storage when explicitly enabled" do
    parent = self()

    runner = fn kind, command, args ->
      send(parent, {kind, command, args})
      {"", 0}
    end

    instance =
      Instance.new(:demo,
        backend: :libvirt,
        backend_config: [remove_storage: true, remove_nvram: false]
      )

    assert :ok = Libvirt.delete(instance, libvirt_runner: runner)

    assert_received {:virsh, "virsh", ["undefine", "demo", "--remove-all-storage"]}
  end
end
