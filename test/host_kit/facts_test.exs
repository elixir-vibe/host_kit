defmodule HostKit.FactsTest do
  use HostKit.Case, async: true

  defmodule Runner do
    def cmd("sh", ["-c", "cat /etc/os-release 2>/dev/null || true"], _opts) do
      {"NAME=DemoOS\nVERSION_ID=1\n", 0}
    end

    def cmd("uname", ["-sr"], _opts), do: {"Linux 1.2.3\n", 0}

    def cmd("getent", ["passwd"], _opts),
      do: {"root:x:0:0:root:/root:/bin/sh\ndemo:x:1000:1000::/home/demo:/bin/sh\n", 0}

    def cmd("systemctl", ["--version"], _opts), do: {"systemd 255\n+PAM\n", 0}
    def cmd("systemctl", ["--failed", "--plain", "--no-legend"], _opts), do: {"", 0}
    def cmd("ss", ["-ltnp"], _opts), do: {"LISTEN 0 4096 127.0.0.1:4000\n", 0}
  end

  test "collects selected facts through runner boundary" do
    assert {:ok, facts} = HostKit.Facts.collect(runner: Runner, only: [:os, :users])

    assert facts.os.os_release["NAME"] == "DemoOS"
    assert facts.os.kernel == "Linux 1.2.3"
    assert Enum.map(facts.users, & &1.name) == ["root", "demo"]
    assert hd(facts.users).uid == 0
    refute Map.has_key?(facts, :ports)
  end

  test "collects structured listening ports" do
    assert {:ok, facts} = HostKit.Facts.collect(runner: Runner, only: [:ports])

    assert facts.ports == [%{address: "127.0.0.1", port: 4000, process: ""}]
  end
end
