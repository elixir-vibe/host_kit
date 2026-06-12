defmodule HostKit.Plan do
  @moduledoc "Structural plan generated from a HostKit project."

  alias HostKit.{Project, Resource}

  @type t :: %__MODULE__{
          project: Project.t(),
          resources: [struct()],
          summary: map(),
          opts: keyword()
        }

  defstruct project: nil,
            resources: [],
            summary: %{},
            opts: []

  @spec build(Project.t(), keyword()) :: {:ok, t()}
  def build(%Project{} = project, opts \\ []) do
    resources = Project.resources(project)

    {:ok,
     %__MODULE__{
       project: project,
       resources: resources,
       summary: summarize(resources),
       opts: opts
     }}
  end

  defp summarize(resources) do
    resources
    |> Enum.map(&Resource.id/1)
    |> Enum.frequencies_by(fn {kind, _name} -> kind end)
  end
end
