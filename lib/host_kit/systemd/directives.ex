defmodule HostKit.Systemd.Directives do
  @moduledoc "Shared systemd defdirective coercion for DSL and runtime builders."

  @spec coerce(keyword()) :: keyword()
  def coerce(values) do
    Enum.map(values, fn {key, value} -> {key, coerce_value(key, value)} end)
  end

  @spec coerce_value(atom(), term()) :: term()
  def coerce_value(key, values) when key in [:after, :wants, :requires, :wanted_by],
    do: HostKit.Systemd.Target.names(values)

  def coerce_value(:exec_start, %HostKit.CommandLine{command: command, args: args}),
    do: Enum.join([command | args], " ")

  def coerce_value(:exec_start, argv) when is_list(argv), do: Enum.join(argv, " ")
  def coerce_value(:restart, :on_failure), do: "on-failure"
  def coerce_value(:on_calendar, value), do: HostKit.Systemd.Calendar.name(value)
  def coerce_value(_key, value), do: value
end
