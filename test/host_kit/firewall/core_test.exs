defmodule HostKit.FirewallTest do
  use ExUnit.Case, async: true

  test "project firewall declarations compile to inspectable structs" do
    source = """
    use HostKit.DSL

    project :demo do
      firewall do
        allow tcp: 22, from: :any
        allow tcp: [80, 443], from: :any
        allow tcp: 9100, from: {10, 44, 0, 0, 24}
        deny :all
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [firewall] = HostKit.Firewall.policies(project)
    assert firewall.scope == :project

    assert [ssh, http, metrics, deny] = firewall.rules
    assert ssh.action == :allow
    assert ssh.protocol == :tcp
    assert ssh.ports == [22]
    assert ssh.from == :any

    assert http.ports == [80, 443]
    assert metrics.from == {10, 44, 0, 0, 24}
    assert deny.action == :deny
    assert deny.target == :all
  end

  test "host firewall declarations are scoped to host" do
    source = """
    use HostKit.DSL

    project :demo do
      host :prod, at: "example.com" do
        firewall do
          allow tcp: 22, from: :any
          deny :all
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [firewall] = HostKit.Firewall.policies(project)
    assert firewall.scope == :host
    assert firewall.name == :prod
    assert Enum.map(firewall.rules, & &1.action) == [:allow, :deny]
  end

  test "project resources include a default systemd firewall loader" do
    source = """
    use HostKit.DSL

    project :demo do
      prefixes unit: "demo-"

      firewall do
        allow tcp: 22, from: :any
        deny :all
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    resources = HostKit.Project.resources(project)

    assert [%HostKit.Firewall{} = firewall] =
             Enum.filter(resources, &match?(%HostKit.Firewall{}, &1))

    assert [%HostKit.Systemd.Service{} = loader] =
             Enum.filter(resources, &match?(%HostKit.Systemd.Service{}, &1))

    assert loader.name == "demo-firewall.service"
    assert loader.service[:exec_start] == "/usr/bin/env nft -f /etc/nftables.d/hostkit.nft"
    assert loader.depends_on == [HostKit.Firewall.id(firewall)]
  end

  test "firewall DSL validates options through DSLCore option schemas" do
    assert_raise ArgumentError, ~r/unknown option :bad for firewall_opts at nofile:4/, fn ->
      Code.eval_string("""
      use HostKit.DSL

      project :demo do
        firewall bad: true do
        end
      end
      """)
    end

    assert_raise ArgumentError,
                 ~r/invalid options for firewall_opts: activate is invalid at nofile:4/,
                 fn ->
                   Code.eval_string("""
                   use HostKit.DSL

                   project :demo do
                     firewall activate: :manual do
                     end
                   end
                   """)
                 end
  end

  test "firewall activation can be disabled" do
    source = """
    use HostKit.DSL

    project :demo do
      firewall activate: false do
        allow tcp: 22, from: :any
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [%HostKit.Firewall{}] = HostKit.Project.resources(project)
  end

  test "renders nftables policy" do
    firewall = %HostKit.Firewall{
      rules: [
        HostKit.Firewall.allow(tcp: 22, from: :any),
        HostKit.Firewall.allow(tcp: [80, 443], from: :any),
        HostKit.Firewall.allow(tcp: 9100, from: {10, 44, 0, 0, 24}),
        HostKit.Firewall.allow(udp: 60000..61000, from: :any),
        HostKit.Firewall.deny(:all)
      ]
    }

    rendered = HostKit.Firewall.Nftables.render(firewall)
    assert rendered =~ "destroy table inet hostkit"
    assert rendered =~ "table inet hostkit"
    assert rendered =~ "type filter hook input priority -100; policy drop"
    assert rendered =~ "tcp dport 22 accept"
    assert rendered =~ "tcp dport { 80, 443 } accept"
    assert rendered =~ "ip saddr 10.44.0.0/24 tcp dport 9100 accept"
    assert rendered =~ "udp dport 60000-61000 accept"
    assert rendered =~ "drop"
  end
end
