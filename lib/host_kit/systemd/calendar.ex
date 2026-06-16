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

  @spec daily_at(String.t() | Time.t()) :: String.t()
  defdelegate daily_at(time), to: Systemd.Calendar

  @spec weekly_at(atom() | String.t(), String.t() | Time.t()) :: String.t()
  defdelegate weekly_at(day, time), to: Systemd.Calendar

  @spec monthly_at(pos_integer(), String.t() | Time.t()) :: String.t()
  defdelegate monthly_at(day, time), to: Systemd.Calendar
end
