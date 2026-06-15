defmodule HostKit.Plan.ExecutionGraph do
  @moduledoc "Builds an inspectable dependency graph for HostKit plan changes."

  alias HostKit.{Change, Plan, Resource}
  alias HostKit.Plan.ExecutionGraph.{Edge, Node}
  alias HostKit.Readiness.Systemd, as: SystemdReadiness

  @type t :: %__MODULE__{
          nodes: [Node.t()],
          edges: [Edge.t()],
          layers: [[term()]],
          cycles: [[term()]]
        }

  defstruct nodes: [], edges: [], layers: [], cycles: []

  @active_actions [:create, :update, :delete]

  @doc "Builds an execution dependency graph from active plan changes."
  @spec build(Plan.t(), keyword()) :: t()
  def build(%Plan{} = plan, _opts \\ []) do
    nodes =
      plan.changes
      |> Enum.filter(&(&1.action in @active_actions))
      |> Enum.map(&graph_node/1)

    by_id = Map.new(nodes, &{&1.id, &1})
    resource_to_node = resource_index(nodes)

    edges =
      nodes
      |> Enum.flat_map(&edges_for(&1, by_id, resource_to_node))
      |> Enum.uniq_by(&{&1.from, &1.to, &1.reason, &1.detail, &1.source})
      |> Enum.sort_by(
        &{format_id(&1.from), format_id(&1.to), to_string(&1.reason), inspect(&1.detail)}
      )

    layers = layers(nodes, edges)
    cycles = cycles(nodes, edges, layers)

    %__MODULE__{nodes: nodes, edges: edges, layers: layers, cycles: cycles}
  end

  @doc "Returns true when the graph has no cycle diagnostics."
  @spec acyclic?(t()) :: boolean()
  def acyclic?(%__MODULE__{cycles: cycles}), do: cycles == []

  @doc "Returns a JSON-safe map for machine-readable graph output."
  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{} = graph) do
    %{
      "nodes" => Enum.map(graph.nodes, &node_json/1),
      "edges" => Enum.map(graph.edges, &edge_json/1),
      "layers" => Enum.map(graph.layers, fn layer -> Enum.map(layer, &id_json/1) end),
      "cycles" => Enum.map(graph.cycles, fn cycle -> Enum.map(cycle, &id_json/1) end),
      "stats" => %{
        "nodes" => length(graph.nodes),
        "edges" => length(graph.edges),
        "layers" => length(graph.layers),
        "cycles" => length(graph.cycles)
      }
    }
  end

  @doc "Formats a concise text rendering of the execution graph."
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = graph) do
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
      format_cycles(graph.cycles),
      format_edges(graph.edges),
      format_layers(graph)
    ]
    |> IO.iodata_to_binary()
    |> String.trim_trailing()
  end

  defp resource_index(nodes) do
    Map.new(nodes, fn node -> {node.resource_id, node.id} end)
    |> Map.merge(Map.new(nodes, fn node -> {normalize_dependency(node.resource_id), node.id} end))
  end

  defp graph_node(%Change{} = change) do
    resource = change.after || change.before

    %Node{
      id: change.resource_id,
      change: change,
      resource_id: change.resource_id,
      action: change.action,
      resource_type: resource && resource.__struct__
    }
  end

  defp edges_for(%Node{} = node, by_id, resource_to_node) do
    resource = node.change.after || node.change.before

    []
    |> add_declared_dependencies(node, resource, resource_to_node)
    |> add_parent_directory(node, resource, by_id)
    |> add_account_edges(node, resource, resource_to_node)
    |> add_command_input_edges(node, resource, resource_to_node)
    |> add_readiness_edges(node, resource, resource_to_node)
  end

  defp add_declared_dependencies(edges, _node, nil, _resource_to_node), do: edges

  defp add_declared_dependencies(edges, node, resource, resource_to_node) do
    resource
    |> Map.get(:depends_on, [])
    |> List.wrap()
    |> Enum.reduce(edges, fn dependency, acc ->
      dependency = normalize_dependency(dependency)

      case Map.fetch(resource_to_node, dependency) do
        {:ok, dependency_node} ->
          [
            dependency_edge(
              dependency_node,
              node.id,
              node.action,
              :explicit_dependency,
              dependency,
              :declared
            )
            | acc
          ]

        :error ->
          acc
      end
    end)
  end

  defp add_parent_directory(edges, node, %{path: path}, by_id) when is_binary(path) do
    parent = Path.dirname(path)
    parent_id = {:directory, parent}

    if parent not in [".", path] and Map.has_key?(by_id, parent_id) do
      [
        dependency_edge(parent_id, node.id, node.action, :parent_directory, parent, :derived)
        | edges
      ]
    else
      edges
    end
  end

  defp add_parent_directory(edges, _node, _resource, _by_id), do: edges

  defp add_account_edges(edges, _node, nil, _resource_to_node), do: edges

  defp add_account_edges(edges, node, resource, resource_to_node) do
    owner = Map.get(resource, :owner)
    group = Map.get(resource, :group)

    edges
    |> add_account_edge(node, owner, :owner_account, resource_to_node)
    |> maybe_add_group_account_edge(node, owner, group, resource_to_node)
  end

  defp maybe_add_group_account_edge(edges, _node, account, account, _resource_to_node), do: edges

  defp maybe_add_group_account_edge(edges, node, _owner, group, resource_to_node) do
    add_account_edge(edges, node, group, :group_account, resource_to_node)
  end

  defp add_account_edge(edges, _node, nil, _reason, _resource_to_node), do: edges

  defp add_account_edge(edges, node, account, reason, resource_to_node) do
    account_id = {:account, account}

    case Map.fetch(resource_to_node, account_id) do
      {:ok, account_node} ->
        [dependency_edge(account_node, node.id, node.action, reason, account, :derived) | edges]

      :error ->
        edges
    end
  end

  defp add_command_input_edges(edges, node, %{inputs: inputs}, resource_to_node)
       when is_list(inputs) do
    Enum.reduce(inputs, edges, fn
      input, acc when is_atom(input) ->
        source_id = {:source, input}

        case Map.fetch(resource_to_node, source_id) do
          {:ok, source_node} ->
            [
              dependency_edge(source_node, node.id, node.action, :source_input, input, :derived)
              | acc
            ]

          :error ->
            acc
        end

      _input, acc ->
        acc
    end)
  end

  defp add_command_input_edges(edges, _node, _resource, _resource_to_node), do: edges

  defp add_readiness_edges(edges, node, %{checks: checks}, resource_to_node)
       when is_list(checks) do
    Enum.reduce(checks, edges, fn
      %SystemdReadiness{unit: unit}, acc ->
        unit
        |> systemd_service_ids()
        |> Enum.find_value(&Map.get(resource_to_node, &1))
        |> case do
          nil ->
            acc

          service_node ->
            [
              dependency_edge(
                service_node,
                node.id,
                node.action,
                :readiness_systemd,
                unit,
                :derived
              )
              | acc
            ]
        end

      _check, acc ->
        acc
    end)
  end

  defp add_readiness_edges(edges, _node, _resource, _resource_to_node), do: edges

  defp systemd_service_ids(unit) do
    stripped = String.replace_suffix(unit, ".service", "")
    [{:systemd_service, unit}, {:systemd_service, stripped}]
  end

  defp dependency_edge(dependency, dependent, :delete, reason, detail, source) do
    %Edge{from: dependent, to: dependency, reason: reason, detail: detail, source: source}
  end

  defp dependency_edge(dependency, dependent, _action, reason, detail, source) do
    %Edge{from: dependency, to: dependent, reason: reason, detail: detail, source: source}
  end

  defp normalize_dependency(%HostKit.Addr.Resource{type: type, name: name}), do: {type, name}
  defp normalize_dependency(%_{} = resource), do: Resource.id(resource)
  defp normalize_dependency(dependency), do: dependency

  defp layers(nodes, edges) do
    node_ids = Enum.map(nodes, & &1.id)
    incoming = Map.new(node_ids, &{&1, MapSet.new()})

    incoming =
      Enum.reduce(edges, incoming, fn edge, incoming ->
        Map.update!(incoming, edge.to, &MapSet.put(&1, edge.from))
      end)

    build_layers(incoming, [])
  end

  defp build_layers(incoming, acc) when map_size(incoming) == 0,
    do: Enum.reverse(acc)

  defp build_layers(incoming, acc) do
    ready =
      incoming
      |> Enum.filter(fn {_id, deps} -> MapSet.size(deps) == 0 end)
      |> Enum.map(fn {id, _deps} -> id end)
      |> Enum.sort_by(&format_id/1)

    if ready == [] do
      Enum.reverse(acc)
    else
      ready_set = MapSet.new(ready)

      incoming =
        incoming
        |> Map.drop(ready)
        |> Map.new(fn {id, deps} -> {id, MapSet.difference(deps, ready_set)} end)

      build_layers(incoming, [ready | acc])
    end
  end

  defp cycles(nodes, _edges, layers) do
    layered = layers |> List.flatten() |> MapSet.new()

    nodes
    |> Enum.map(& &1.id)
    |> Enum.reject(&MapSet.member?(layered, &1))
    |> case do
      [] -> []
      remaining -> [Enum.sort_by(remaining, &format_id/1)]
    end
  end

  defp format_cycles([]), do: []

  defp format_cycles(cycles) do
    cycles
    |> Enum.map(fn cycle -> ["\nCycle: ", Enum.map_join(cycle, " -> ", &format_id/1)] end)
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

  defp id_json(id), do: %{"display" => format_id(id), "term" => Resource.dump(id)}

  defp detail_json(nil), do: nil

  defp detail_json(detail) when is_binary(detail) or is_number(detail) or is_boolean(detail),
    do: detail

  defp detail_json(detail) when is_atom(detail), do: Atom.to_string(detail)
  defp detail_json(detail), do: Resource.dump(detail)

  defp module_json(nil), do: nil
  defp module_json(module) when is_atom(module), do: Atom.to_string(module)

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

  defp format_detail(detail) when is_binary(detail), do: detail
  defp format_detail(detail) when is_atom(detail), do: Atom.to_string(detail)
  defp format_detail(detail), do: inspect(detail)

  defp format_layers(%__MODULE__{layers: []}), do: []

  defp format_layers(%__MODULE__{} = graph) do
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

  defp format_layer_node(%Node{} = node) do
    [node.action |> Atom.to_string(), " ", format_id(node.id)]
  end

  defp format_id(%HostKit.Addr.Resource{} = resource), do: to_string(resource)
  defp format_id({type, name}), do: "#{type}.#{name}"
  defp format_id(id), do: inspect(id)
end
