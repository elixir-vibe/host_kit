defmodule HostKit.Instance.IncusBackendTest do
  use ExUnit.Case, async: true

  alias HostKit.Instance
  alias HostKit.Instance.Backends.Incus

  test "read reports missing Incus command as an error" do
    instance = Instance.new(:demo, backend: :incus, image: "images:ubuntu/24.04")

    assert {:error, {:incus_command_failed, reason}} =
             Incus.read(instance, incus: "/definitely/missing/incus")

    assert reason =~ ":enoent"
  end

  test "apply launches exposes ports and starts the instance" do
    parent = self()

    runner = fn command, args ->
      send(parent, {command, args})

      case args do
        ["info", "demo"] -> {"not found", 1}
        _args -> {"", 0}
      end
    end

    instance =
      Instance.new(:demo, backend: :incus, image: "images:ubuntu/24.04", kind: :container)
      |> Instance.add_port(:ssh, host: 2222, guest: 22)
      |> Instance.add_port(:web, host: 18_080, guest: 80)

    assert :ok = Incus.apply(instance, incus: "incus", incus_runner: runner)

    assert_received {"incus", ["info", "demo"]}
    assert_received {"incus", ["launch", "images:ubuntu/24.04", "demo"]}

    assert_received {"incus",
                     [
                       "config",
                       "device",
                       "add",
                       "demo",
                       "hostkit-ssh",
                       "proxy",
                       "listen=tcp:127.0.0.1:2222",
                       "connect=tcp:127.0.0.1:22"
                     ]}

    assert_received {"incus",
                     [
                       "config",
                       "device",
                       "add",
                       "demo",
                       "hostkit-web",
                       "proxy",
                       "listen=tcp:127.0.0.1:18080",
                       "connect=tcp:127.0.0.1:80"
                     ]}

    assert_received {"incus", ["start", "demo"]}
    assert_received {"incus", ["exec", "demo", "--", "true"]}
  end

  test "apply replaces legacy demo proxy devices when ports are already bound" do
    parent = self()

    {:ok, calls} = Agent.start_link(fn -> %{} end)

    runner = fn _command, args ->
      send(parent, args)

      count =
        Agent.get_and_update(calls, fn counts ->
          {Map.get(counts, args, 0), Map.update(counts, args, 1, &(&1 + 1))}
        end)

      case {args, count} do
        {["info", "demo"], _count} ->
          {"present", 0}

        {["config", "device", "add", "demo", "hostkit-ssh", "proxy", _listen, _connect], 0} ->
          {"address already in use", 1}

        {_args, _count} ->
          {"", 0}
      end
    end

    instance =
      Instance.new(:demo, backend: :incus, image: "images:ubuntu/24.04")
      |> Instance.add_port(:ssh, host: 2222, guest: 22)

    assert :ok = Incus.apply(instance, incus_runner: runner)

    assert_received ["config", "device", "remove", "demo", "sshproxy"]
  end

  test "apply configures root password ssh when a nested host declares it" do
    parent = self()

    runner = fn _command, args ->
      send(parent, args)

      case args do
        ["info", "demo"] -> {"present", 0}
        _args -> {"", 0}
      end
    end

    host = %HostKit.Host{
      name: :guest,
      hostname: "127.0.0.1",
      user: "root",
      meta: %{ssh: [password: "secret"]}
    }

    instance = %Instance{name: :demo, backend: :incus, hosts: [host]}

    assert :ok = Incus.apply(instance, incus_runner: runner)

    assert_received ["exec", "demo", "--", "true"]
    assert_received ["exec", "demo", "--", "sh", "-c", script]
    assert script =~ "apt-get install -y openssh-server"
    assert script =~ "PermitRootLogin yes"
    assert script =~ "'secret' | chpasswd"
  end

  test "apply uses vm launch flag for VM instances" do
    parent = self()

    runner = fn _command, args ->
      send(parent, args)

      case args do
        ["info", "demo"] -> {"not found", 1}
        _args -> {"", 0}
      end
    end

    instance = Instance.new(:demo, backend: :incus, image: "images:ubuntu/24.04", kind: :vm)

    assert :ok = Incus.apply(instance, incus_runner: runner)
    assert_received ["launch", "images:ubuntu/24.04", "demo", "--vm"]
  end
end
