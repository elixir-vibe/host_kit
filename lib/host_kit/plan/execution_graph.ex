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

    indexes = %{
      by_id: Map.new(nodes, &{&1.id, &1}),
      resource_to_node: resource_index(nodes),
      path_to_node: path_index(nodes),
      directory_paths: directory_paths(nodes)
    }

    edges =
      nodes
      |> Enum.flat_map(&edges_for(&1, indexes))
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

  defp path_index(nodes) do
    nodes
    |> Enum.flat_map(fn node ->
      case node.change.after || node.change.before do
        %{path: path} when is_binary(path) -> [{path, node.id}]
        _resource -> []
      end
    end)
    |> Map.new()
  end

  defp directory_paths(nodes) do
    nodes
    |> Enum.flat_map(fn node ->
      case node.change.after || node.change.before do
        %HostKit.Resources.Directory{path: path} when is_binary(path) -> [{path, node.id}]
        _resource -> []
      end
    end)
    |> Map.new()
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

  defp edges_for(%Node{} = node, indexes) do
    resource = node.change.after || node.change.before

    []
    |> add_declared_dependencies(node, resource, indexes.resource_to_node)
    |> add_parent_directory(node, resource, indexes.path_to_node)
    |> add_account_edges(node, resource, indexes.resource_to_node)
    |> add_command_input_edges(node, resource, indexes.resource_to_node)
    |> add_readiness_edges(node, resource, indexes.resource_to_node)
    |> add_symlink_target_edges(node, resource, indexes)
    |> add_systemd_timer_edges(node, resource, indexes.resource_to_node)
    |> add_systemd_service_path_edges(node, resource, indexes.path_to_node)
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

  defp add_parent_directory(edges, node, %{path: path}, path_to_node) when is_binary(path) do
    parent = Path.dirname(path)

    case Map.fetch(path_to_node, parent) do
      {:ok, parent_node} when parent not in [".", path] ->
        [
          dependency_edge(parent_node, node.id, node.action, :parent_directory, parent, :derived)
          | edges
        ]

      _other ->
        edges
    end
  end

  defp add_parent_directory(edges, _node, _resource, _path_to_node), do: edges

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

  defp add_symlink_target_edges(edges, node, %HostKit.Resources.Symlink{to: target}, indexes)
       when is_binary(target) do
    target
    |> nearest_path_node(indexes.directory_paths, node.id)
    |> case do
      nil ->
        edges

      target_node ->
        [
          dependency_edge(
            target_node,
            node.id,
            node.action,
            :symlink_target_path,
            target,
            :derived
          )
          | edges
        ]
    end
  end

  defp add_symlink_target_edges(edges, _node, _resource, _indexes), do: edges

  defp add_systemd_timer_edges(edges, node, %HostKit.Systemd.Timer{name: name}, resource_to_node) do
    name
    |> String.replace_suffix(".timer", ".service")
    |> systemd_service_ids()
    |> Enum.find_value(&Map.get(resource_to_node, &1))
    |> case do
      nil ->
        edges

      service_node ->
        [
          dependency_edge(
            service_node,
            node.id,
            node.action,
            :systemd_timer_service,
            name,
            :derived
          )
          | edges
        ]
    end
  end

  defp add_systemd_timer_edges(edges, _node, _resource, _resource_to_node), do: edges

  defp add_systemd_service_path_edges(
         edges,
         node,
         %HostKit.Systemd.Service{service: service},
         path_to_node
       ) do
    edges
    |> add_paths(
      node,
      directive_paths(service, :environment_file),
      path_to_node,
      :systemd_environment_file
    )
    |> add_paths(
      node,
      directive_paths(service, :read_write_paths),
      path_to_node,
      :systemd_read_write_path
    )
    |> add_exec_path(node, Keyword.get(service, :exec_start), path_to_node)
  end

  defp add_systemd_service_path_edges(edges, _node, _resource, _path_to_node), do: edges

  defp add_paths(edges, node, paths, path_to_node, reason) do
    Enum.reduce(paths, edges, fn path, acc ->
      case Map.fetch(path_to_node, path) do
        {:ok, path_node} ->
          [dependency_edge(path_node, node.id, node.action, reason, path, :derived) | acc]

        :error ->
          acc
      end
    end)
  end

  defp add_exec_path(edges, _node, nil, _path_to_node), do: edges

  defp add_exec_path(edges, node, exec_start, path_to_node) when is_binary(exec_start) do
    exec = exec_start |> String.split(~r/\s+/, parts: 2) |> List.first()

    exec
    |> nearest_path_node(path_to_node, node.id)
    |> case do
      nil ->
        edges

      exec_node ->
        [
          dependency_edge(exec_node, node.id, node.action, :systemd_exec_path, exec, :derived)
          | edges
        ]
    end
  end

  defp add_exec_path(edges, _node, _exec_start, _path_to_node), do: edges

  defp directive_paths(service, key) do
    service
    |> Keyword.get_values(key)
    |> Enum.flat_map(&List.wrap/1)
    |> Enum.flat_map(&split_systemd_paths/1)
  end

  defp split_systemd_paths(value) when is_binary(value) do
    value
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.trim_leading(&1, "-"))
    |> Enum.filter(&String.starts_with?(&1, "/"))
  end

  defp split_systemd_paths(value),
    do: value |> List.wrap() |> Enum.flat_map(&split_systemd_paths/1)

  defp nearest_path_node(path, path_to_node, excluded_node) do
    path
    |> path_candidates()
    |> Enum.find_value(fn candidate ->
      case Map.get(path_to_node, candidate) do
        ^excluded_node -> nil
        nil -> nil
        node -> node
      end
    end)
  end

  defp path_candidates(path) do
    path
    |> Path.expand()
    |> Stream.iterate(&Path.dirname/1)
    |> Enum.reduce_while([], fn
      ".", acc -> {:halt, acc}
      "/", acc -> {:halt, ["/" | acc]}
      path, acc -> if path in acc, do: {:halt, acc}, else: {:cont, [path | acc]}
    end)
    |> Enum.reverse()
  end

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
