defmodule HostKit.Net.Addr do
  @moduledoc "Network address normalization helpers."

  import Kernel, except: [to_string: 1]

  @ipv4_any {0, 0, 0, 0}
  @ipv4_loopback {127, 0, 0, 1}
  @ipv6_any {0, 0, 0, 0, 0, 0, 0, 0}
  @ipv6_loopback {0, 0, 0, 0, 0, 0, 0, 1}

  def normalize(:loopback), do: {:ok, @ipv4_loopback}
  def normalize(:localhost), do: {:ok, @ipv4_loopback}
  def normalize(:any), do: {:ok, @ipv4_any}
  def normalize(:all), do: {:ok, @ipv4_any}
  def normalize(:loopback_v6), do: {:ok, @ipv6_loopback}
  def normalize(:localhost_v6), do: {:ok, @ipv6_loopback}
  def normalize(:any_v6), do: {:ok, @ipv6_any}
  def normalize(:all_v6), do: {:ok, @ipv6_any}

  def normalize({a, b, c, d} = addr)
      when a in 0..255 and b in 0..255 and c in 0..255 and d in 0..255, do: {:ok, addr}

  def normalize({a, b, c, d, prefix} = cidr)
      when a in 0..255 and b in 0..255 and c in 0..255 and d in 0..255 and prefix in 0..32,
      do: {:ok, cidr}

  def normalize({{a, b, c, d}, prefix})
      when a in 0..255 and b in 0..255 and c in 0..255 and d in 0..255 and prefix in 0..32,
      do: {:ok, {a, b, c, d, prefix}}

  def normalize({a, b, c, d, e, f, g, h} = addr)
      when a in 0..65_535 and b in 0..65_535 and c in 0..65_535 and d in 0..65_535 and
             e in 0..65_535 and f in 0..65_535 and g in 0..65_535 and h in 0..65_535,
      do: {:ok, addr}

  def normalize(value) when is_binary(value), do: {:ok, value}
  def normalize(value), do: {:error, {:invalid_network_address, value}}

  def normalize!(value) do
    case normalize(value) do
      {:ok, addr} -> addr
      {:error, reason} -> raise ArgumentError, inspect(reason)
    end
  end

  def to_string(value) do
    value
    |> normalize!()
    |> render()
  end

  def systemd_allow(:loopback), do: "localhost"
  def systemd_allow(:localhost), do: "localhost"
  def systemd_allow(value), do: to_string(value)

  def systemd_deny(:all), do: "any"
  def systemd_deny(:any), do: "any"
  def systemd_deny(value), do: to_string(value)

  defp render({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp render({a, b, c, d, prefix}), do: "#{a}.#{b}.#{c}.#{d}/#{prefix}"

  defp render({a, b, c, d, e, f, g, h}) do
    Enum.map_join([a, b, c, d, e, f, g, h], ":", &Integer.to_string(&1, 16))
  end

  defp render(value) when is_binary(value), do: value
end
