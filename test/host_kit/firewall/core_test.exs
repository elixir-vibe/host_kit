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
