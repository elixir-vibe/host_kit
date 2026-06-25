defmodule HostKit.FirewallApplyTest do
  use ExUnit.Case, async: true

  alias HostKit.{Apply, Change, Firewall, Plan}

  defmodule Runner do
    @behaviour HostKit.Runner

    @impl true
    def cmd(command, args, opts) do
      send(opts[:test_pid], {:cmd, command, args})
      {"", 0}
    end

    @impl true
    def mkdir_p(path, opts) do
      send(opts[:test_pid], {:mkdir_p, path})
      :ok
    end

    @impl true
    def write_file(path, content, opts) do
      send(opts[:test_pid], {:write_file, path, IO.iodata_to_binary(content)})
      :ok
    end
  end

  test "applies firewall policy as nftables file" do
    firewall = %Firewall{
      path: "/etc/nftables.d/hostkit.nft",
      rules: [
        Firewall.allow(tcp: 22, from: :any),
        Firewall.allow(tcp: [80, 443], from: :any),
        Firewall.deny(:all)
      ]
    }

    plan = %Plan{
      changes: [%Change{action: :create, resource_id: Firewall.id(firewall), after: firewall}]
    }

    assert {:ok, [%{status: :applied}]} =
             Apply.run(plan,
               confirm: true,
               runner: {Runner, test_pid: self()},
               nft_reload: true
             )

    assert_received {:mkdir_p, "/etc/nftables.d"}
    assert_received {:write_file, "/etc/nftables.d/hostkit.nft", content}
    assert content =~ "table inet hostkit"
    assert content =~ "tcp dport { 80, 443 } accept"
    assert_received {:cmd, "chown", ["root:root", "/etc/nftables.d/hostkit.nft"]}
    assert_received {:cmd, "chmod", ["0644", "/etc/nftables.d/hostkit.nft"]}
    assert_received {:cmd, "nft", ["-c", "-f", "/etc/nftables.d/hostkit.nft"]}
    assert_received {:cmd, "nft", ["-f", "/etc/nftables.conf"]}
  end
end
