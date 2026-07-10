defmodule HostKit.Plan.ExecutionGraph do
  @moduledoc "Builds an inspectable dependency graph for HostKit plan changes."

  alias HostKit.{Change, Diagnostic, Diagnostics, Plan, Resource}
  alias HostKit.Plan.ExecutionGraph.{Build, Edge, Format, JSON, Node}

  @type t :: %__MODULE__{
          nodes: [Node.t()],
          edges: [Edge.t()],
          layers: [[term()]],
          cycles: [[term()]]
        }

  defstruct nodes: [], edges: [], layers: [], cycles: []

  @doc "Builds an execution dependency graph from active plan changes."
  @spec build(Plan.t(), keyword()) :: t()
  defdelegate build(plan, opts \\ []), to: Build

  @doc "Returns true when the graph has no cycle diagnostics."
  @spec acyclic?(t()) :: boolean()
  def acyclic?(%__MODULE__{cycles: cycles}), do: cycles == []

  @doc "Validates resource identities and declared execution dependencies."
  @spec validate(Plan.t()) :: :ok | {:error, Diagnostics.t()}
  def validate(%Plan{changes: changes} = plan) do
    diagnostics =
      changes
      |> duplicate_id_diagnostics()
      |> Kernel.++(missing_dependency_diagnostics(changes))
      |> Kernel.++(cycle_diagnostics(plan))
      |> Diagnostics.new()

    if Diagnostics.ok?(diagnostics), do: :ok, else: {:error, diagnostics}
  end

  @doc "Returns a JSON-safe map for machine-readable graph output."
  @spec to_json(t()) :: map()
  defdelegate to_json(graph), to: JSON

  @doc "Formats a concise text rendering of the execution graph."
  @spec format(t()) :: String.t()
  defdelegate format(graph), to: Format

  defp duplicate_id_diagnostics(changes) do
    changes
    |> Enum.frequencies_by(& &1.resource_id)
    |> Enum.flat_map(fn
      {_resource_id, 1} ->
        []

      {resource_id, count} ->
        [
          %Diagnostic{
            code: :duplicate_resource_id,
            message: "resource id is declared more than once: #{inspect(resource_id)}",
            resource_id: resource_id,
            details: %{count: count},
            hint: "Give every resource in a plan a unique identity."
          }
        ]
    end)
  end

  defp missing_dependency_diagnostics(changes) do
    ids = MapSet.new(changes, &normalize_dependency(&1.resource_id))

    changes
    |> Enum.flat_map(fn %Change{} = change ->
      change
      |> change_resource()
      |> declared_dependencies()
      |> Enum.reject(&MapSet.member?(ids, &1))
      |> Enum.map(fn dependency ->
        %Diagnostic{
          code: :missing_dependency,
          message:
            "resource #{inspect(change.resource_id)} depends on missing resource #{inspect(dependency)}",
          resource_id: change.resource_id,
          details: %{dependency: dependency},
          hint: "Declare the dependency or remove it from depends_on."
        }
      end)
    end)
    |> Enum.uniq_by(&{&1.resource_id, &1.details.dependency})
  end

  defp cycle_diagnostics(%Plan{changes: changes} = plan) do
    if unique_ids?(changes) do
      plan
      |> build(include: :all)
      |> Map.fetch!(:cycles)
      |> Enum.map(fn cycle ->
        %Diagnostic{
          code: :dependency_cycle,
          message: "resource dependency cycle: #{Enum.map_join(cycle, " -> ", &inspect/1)}",
          resource_id: hd(cycle),
          details: %{resources: cycle},
          hint: "Remove one of the dependencies in the cycle."
        }
      end)
    else
      []
    end
  end

  defp unique_ids?(changes) do
    ids = Enum.map(changes, & &1.resource_id)
    length(ids) == MapSet.size(MapSet.new(ids))
  end

  defp change_resource(%Change{after: resource}) when not is_nil(resource), do: resource
  defp change_resource(%Change{before: resource}), do: resource

  defp declared_dependencies(nil), do: []

  defp declared_dependencies(resource) do
    resource
    |> Map.get(:depends_on, [])
    |> List.wrap()
    |> Enum.map(&normalize_dependency/1)
  end

  @doc false
  def normalize_dependency(%HostKit.Addr.Resource{type: type, name: name}), do: {type, name}

  def normalize_dependency(%_{} = resource), do: Resource.id(resource)
  def normalize_dependency(dependency), do: dependency
end
