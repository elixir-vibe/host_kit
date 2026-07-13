defmodule HostKit.Plan.ExecutionGraph.JSON do
  @moduledoc false

  alias HostKit.Plan.ExecutionGraph
  alias HostKit.Plan.ExecutionGraph.{Edge, Node}
  import HostKit.Plan.ExecutionGraph.Helpers, only: [cycle_edges: 2, format_id: 1]

  @spec to_json(ExecutionGraph.t()) :: map()
  def to_json(%ExecutionGraph{} = graph) do
    %{
      "nodes" => Enum.map(graph.nodes, &node_json/1),
      "edges" => Enum.map(graph.edges, &edge_json/1),
      "layers" => Enum.map(graph.layers, fn layer -> Enum.map(layer, &id_json/1) end),
      "cycles" => Enum.map(graph.cycles, fn cycle -> Enum.map(cycle, &id_json/1) end),
      "cycle_edges" => cycle_edges_json(graph.cycles, graph.edges),
      "stats" => %{
        "nodes" => length(graph.nodes),
        "edges" => length(graph.edges),
        "layers" => length(graph.layers),
        "cycles" => length(graph.cycles)
      }
    }
  end

  defp node_json(%Node{} = node) do
    %{
      "id" => id_json(node.id),
      "display" => format_id(node.id),
      "action" => Atom.to_string(node.action),
      "resource_type" => module_json(node.resource_type)
    }
  end

  defp edge_json(%Edge{} = edge) do
    %{
      "from" => id_json(edge.from),
      "to" => id_json(edge.to),
      "from_display" => format_id(edge.from),
      "to_display" => format_id(edge.to),
      "reason" => Atom.to_string(edge.reason),
      "detail" => detail_json(edge.detail),
      "source" => Atom.to_string(edge.source)
    }
  end

  defp cycle_edges_json(cycles, edges) do
    Enum.map(cycles, fn cycle -> Enum.map(cycle_edges(cycle, edges), &edge_json/1) end)
  end

  defp id_json(id),
    do: %{"display" => format_id(id), "term" => HostKit.Resource.dump(id)}

  defp detail_json(nil), do: nil

  defp detail_json(detail) when is_binary(detail) or is_number(detail) or is_boolean(detail),
    do: detail

  defp detail_json(detail) when is_atom(detail), do: Atom.to_string(detail)
  defp detail_json(detail), do: HostKit.Resource.dump(detail)

  defp module_json(nil), do: nil
  defp module_json(module) when is_atom(module), do: Atom.to_string(module)
end
