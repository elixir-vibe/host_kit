defmodule HostKit.Instance.IncusBackendTest do
  use ExUnit.Case, async: true

  alias HostKit.Instance
  alias HostKit.Instance.Backends.Incus

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
                       "listen=tcp:0.0.0.0:2222",
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
                       "listen=tcp:0.0.0.0:18080",
                       "connect=tcp:127.0.0.1:80"
                     ]}

    assert_received {"incus", ["start", "demo"]}
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
