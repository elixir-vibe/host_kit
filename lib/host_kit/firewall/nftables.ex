defmodule HostKit.Firewall.Nftables do
  @moduledoc "Render HostKit firewall policy to nftables syntax."

  alias HostKit.Firewall
  alias HostKit.Firewall.Rule

  @spec render(Firewall.t()) :: String.t()
  def render(%Firewall{} = firewall) do
    rules = Enum.map_join(firewall.rules, "\n", &render_rule/1)

    """
    table inet hostkit {
      chain input {
        type filter hook input priority 0; policy drop;

        ct state established,related accept
        iif lo accept
    #{indent(rules, 4)}
      }
    }
    """
  end

  defp render_rule(%Rule{action: :allow, protocol: protocol, ports: ports, from: from}) do
    source = source_match(from)
    ports = ports_match(protocol, ports)

    [source, ports, "accept"]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp render_rule(%Rule{action: :deny, target: :all}), do: "drop"
  defp render_rule(%Rule{action: :deny, target: target}), do: "#{source_match(target)} drop"

  def render_egress(%HostKit.Workspace.Egress{} = egress) do
    allow =
      egress.allow |> List.wrap() |> Enum.map_join("\n", &render_egress_allow(egress.user, &1))

    """
    table inet hostkit_egress {
      chain output {
        type filter hook output priority 0; policy accept;
    #{indent(allow, 4)}
      }
    }
    """
  end

  defp render_egress_allow(user, :dns), do: "meta skuid #{user} udp dport 53 accept"
  defp render_egress_allow(user, :https), do: "meta skuid #{user} tcp dport 443 accept"
  defp render_egress_allow(user, :http), do: "meta skuid #{user} tcp dport 80 accept"

  defp render_egress_allow(user, value),
    do: "meta skuid #{user} ip daddr #{HostKit.Net.Addr.to_string(value)} accept"

  defp source_match(nil), do: ""
  defp source_match(:any), do: ""
  defp source_match(:all), do: ""
  defp source_match(from), do: "ip saddr #{HostKit.Net.Addr.to_string(from)}"

  defp ports_match(:icmp, _ports), do: "icmp type echo-request"
  defp ports_match(protocol, [port]), do: "#{protocol} dport #{port}"
  defp ports_match(protocol, ports), do: "#{protocol} dport { #{Enum.join(ports, ", ")} }"

  defp indent("", _spaces), do: ""

  defp indent(text, spaces) do
    prefix = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", &(prefix <> &1))
  end
end
