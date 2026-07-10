defmodule Mix.Tasks.HostKit.Output do
  @moduledoc false

  def format_plan(plan, opts) do
    output =
      case Keyword.get(opts, :format, "text") do
        "text" -> HostKit.Plan.Format.format(plan)
        "inspect" -> inspect(plan, pretty: true, limit: :infinity, structs: true)
      end

    if graph_output?(opts) do
      graph = HostKit.Plan.ExecutionGraph.build(plan)
      output <> "\n\n" <> format_graph(graph, opts)
    else
      output
    end
  end

  defp graph_output?(opts) do
    Keyword.get(opts, :show_graph, false) or Keyword.has_key?(opts, :graph_format)
  end

  defp format_graph(graph, opts) do
    case Keyword.get(opts, :graph_format, "text") do
      "text" ->
        HostKit.Plan.ExecutionGraph.format(graph)

      "json" ->
        graph
        |> HostKit.Plan.ExecutionGraph.to_json()
        |> Jason.encode_to_iodata!(pretty: true)
        |> IO.iodata_to_binary()

      format ->
        Mix.raise("unknown --graph-format #{inspect(format)}, expected text or json")
    end
  end

  def print_results(results) do
    results
    |> Enum.map_join("\n", fn %{change: change, status: status} ->
      "#{status} #{HostKit.Plan.Format.format_change(change)}"
    end)
    |> IO.puts()
  end

  def format_counts(counts) when map_size(counts) == 0, do: "none"

  def format_counts(counts) do
    Enum.map_join(counts, ", ", fn {type, count} -> "#{type}=#{count}" end)
  end
end
