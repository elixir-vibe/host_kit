defmodule HostKit.Render do
  @moduledoc "Renders resources through core and plugin renderers."

  alias HostKit.{Plugin, Project, Resource}

  @spec render(Project.t(), term(), map()) :: {:ok, iodata()} | {:error, term()}
  def render(%Project{} = project, resource_id, context \\ %{}) do
    with {:ok, resource} <- find_resource(project, resource_id) do
      Plugin.render(project.plugins, resource, context)
    end
  end

  @spec find_resource(Project.t(), term()) :: {:ok, struct()} | {:error, :not_found}
  def find_resource(%Project{} = project, resource_id) do
    case Enum.find(Project.resources(project), &(Resource.id(&1) == resource_id)) do
      nil -> {:error, :not_found}
      resource -> {:ok, resource}
    end
  end
end
