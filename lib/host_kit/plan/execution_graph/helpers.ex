defmodule HostKit.Plan.ExecutionGraph.Helpers do
  @moduledoc false

  def cycle_edges(cycle, edges) do
    cycle_set = MapSet.new(cycle)

    edges
    |> Enum.filter(&(MapSet.member?(cycle_set, &1.from) and MapSet.member?(cycle_set, &1.to)))
    |> Enum.sort_by(
      &{format_id(&1.from), format_id(&1.to), to_string(&1.reason), inspect(&1.detail)}
    )
  end

  def format_id(%HostKit.Addr.Resource{} = resource), do: to_string(resource)
  def format_id({type, name}), do: "#{type}.#{name}"
  def format_id(id), do: inspect(id)
end
