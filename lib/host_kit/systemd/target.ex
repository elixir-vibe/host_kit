defmodule HostKit.Systemd.Target do
  @moduledoc "Systemd target reference helpers."

  @aliases %{
    multi_user: "multi-user.target",
    graphical: "graphical.target",
    timers: "timers.target",
    network: "network.target",
    network_online: "network-online.target",
    default: "default.target"
  }

  @spec name(atom() | String.t()) :: String.t()
  def name(target) when is_atom(target), do: Map.get(@aliases, target, Atom.to_string(target))
  def name(target) when is_binary(target), do: target

  @spec names(atom() | String.t() | [atom() | String.t()]) :: String.t() | [String.t()]
  def names(targets) when is_list(targets), do: Enum.map(targets, &name/1)
  def names(target), do: name(target)
end
