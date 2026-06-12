defmodule HostKit.Systemd.Calendar do
  @moduledoc "Systemd calendar expression helpers."

  @aliases %{
    hour: "hourly",
    hourly: "hourly",
    day: "daily",
    daily: "daily",
    week: "weekly",
    weekly: "weekly",
    month: "monthly",
    monthly: "monthly",
    year: "yearly",
    yearly: "yearly"
  }

  @spec name(atom() | String.t()) :: String.t()
  def name(value) when is_atom(value), do: Map.get(@aliases, value, Atom.to_string(value))
  def name(value) when is_binary(value), do: value
end
