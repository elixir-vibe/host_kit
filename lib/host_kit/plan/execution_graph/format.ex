defmodule HostKit.Plan.ExecutionGraph.Format do
  @moduledoc false

  alias HostKit.Plan.ExecutionGraph
  alias HostKit.Plan.ExecutionGraph.Node

  import HostKit.Plan.ExecutionGraph.Helpers, only: [cycle_edges: 2, format_id: 1]

  @spec format(ExecutionGraph.t()) :: String.t()
  def format(%ExecutionGraph{} = graph) do
    [
      "Execution graph: ",
      Integer.to_string(length(graph.nodes)),
      " nodes, ",
      Integer.to_string(length(graph.edges)),
      " edges, ",
      Integer.to_string(length(graph.layers)),
      " layers, ",
      Integer.to_string(length(graph.cycles)),
      " cycles",
      format_cycles(graph.cycles, graph.edges),
      format_edges(graph.edges),
      format_layers(graph)
    ]
    |> IO.iodata_to_binary()
    |> String.trim_trailing()
  end

  defp format_cycles([], _edges), do: []

  defp format_cycles(cycles, edges) do
    Enum.map(cycles, fn cycle ->
      cycle_edges = cycle_edges(cycle, edges)

      if cycle_edges == [] do
        ["\nCycle: ", Enum.map_join(cycle, " -> ", &format_id/1)]
      else
        [
          "\nCycle:",
          Enum.map(cycle_edges, fn edge ->
            [
              "\n  ",
              format_id(edge.from),
              " -> ",
              format_id(edge.to),
              " [",
              Atom.to_string(edge.reason),
              format_edge_detail(edge.detail),
              "]"
            ]
          end)
        ]
      end
    end)
  end

  defp format_edges([]), do: []

  defp format_edges(edges) do
    [
      "\n\nEdges:",
      Enum.map(edges, fn edge ->
        [
          "\n  ",
          format_id(edge.from),
          " -> ",
          format_id(edge.to),
          " [",
          Atom.to_string(edge.reason),
          format_edge_detail(edge.detail),
          "]"
        ]
      end)
    ]
  end

  defp format_edge_detail(nil), do: ""
  defp format_edge_detail(detail), do: ": " <> format_detail(detail)

  defp format_detail(%HostKit.Addr.Resource{} = detail), do: format_id(detail)
  defp format_detail({type, name}) when is_atom(type), do: format_id({type, name})
  defp format_detail(detail) when is_binary(detail), do: detail
  defp format_detail(detail) when is_atom(detail), do: Atom.to_string(detail)
  defp format_detail(detail), do: inspect(detail)

  defp format_layers(%ExecutionGraph{layers: []}), do: []

  defp format_layers(%ExecutionGraph{} = graph) do
    node_by_id = Map.new(graph.nodes, &{&1.id, &1})

    graph.layers
    |> Enum.with_index(1)
    |> Enum.map(fn {layer, index} ->
      [
        "\n\nLayer ",
        Integer.to_string(index),
        ":",
        Enum.map(layer, fn id -> ["\n  ", format_layer_node(Map.fetch!(node_by_id, id))] end)
      ]
    end)
  end

  defp format_layer_node(%Node{} = node),
    do: [Atom.to_string(node.action), " ", format_id(node.id)]
end
