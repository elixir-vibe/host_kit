defmodule HostKit.Plan do
  @moduledoc "Structural plan generated from a HostKit project."

  alias HostKit.Addr
  alias HostKit.{Change, Project, Resource}

  @type t :: %__MODULE__{
          project: Project.t(),
          resources: [struct()],
          changes: [Change.t()],
          summary: map(),
          opts: keyword()
        }

  defstruct project: nil,
            resources: [],
            changes: [],
            summary: %{},
            opts: []

  @spec build(Project.t(), keyword()) :: {:ok, t()}
  def build(%Project{} = project, opts \\ []) do
    resources = Project.resources(project)

    changes = Enum.map(resources, &desired_change/1)

    {:ok,
     %__MODULE__{
       project: project,
       resources: resources,
       changes: changes,
       summary: summarize(changes),
       opts: opts
     }}
  end

  defp desired_change(resource) do
    %Change{
      action: :create,
      resource_id: Resource.id(resource),
      before: nil,
      after: resource,
      reason: :desired_state
    }
  end

  defp summarize(changes) do
    changes
    |> Enum.map(& &1.resource_id)
    |> Enum.frequencies_by(&resource_type/1)
  end

  defp resource_type(%Addr.Resource{type: type}), do: type
  defp resource_type({type, _name}), do: type
  defp resource_type(other), do: other
end
