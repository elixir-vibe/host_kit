defmodule Mix.Tasks.HostKit.Output do
  @moduledoc false

  def format_plan(plan, opts) do
    case Keyword.get(opts, :format, "text") do
      "text" -> HostKit.Plan.Format.format(plan)
      "inspect" -> inspect(plan, pretty: true, limit: :infinity, structs: true)
    end
  end

  def format_counts(counts) when map_size(counts) == 0, do: "none"

  def format_counts(counts) do
    Enum.map_join(counts, ", ", fn {type, count} -> "#{type}=#{count}" end)
  end
end
