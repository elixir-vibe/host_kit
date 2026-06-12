defmodule HostKit.Render do
  @moduledoc "Renders resources through core renderers and optional plugin renderers."

  alias HostKit.{Plugin, Project, Resource}

  @spec render(Project.t(), term(), map()) :: {:ok, iodata()} | {:error, term()}
  def render(%Project{} = project, resource_id, context \\ %{}) do
    with {:ok, resource} <- find_resource(project, resource_id) do
      render_resource(project, resource, context)
    end
  end

  @spec render_resource(Project.t(), struct(), map()) :: {:ok, iodata()} | {:error, term()}
  def render_resource(%Project{} = project, resource, context \\ %{}) do
    case render_core(resource, context) do
      :ignore -> Plugin.render(project.plugins, resource, context)
      result -> result
    end
  end

  @spec find_resource(Project.t(), term()) :: {:ok, struct()} | {:error, :not_found}
  def find_resource(%Project{} = project, resource_id) do
    case Enum.find(Project.resources(project), &(Resource.id(&1) == resource_id)) do
      nil -> {:error, :not_found}
      resource -> {:ok, resource}
    end
  end

  defp render_core(%HostKit.Systemd.Service{} = service, _context),
    do: {:ok, HostKit.Systemd.Service.render(service)}

  defp render_core(%HostKit.Systemd.Timer{} = timer, _context),
    do: {:ok, HostKit.Systemd.Timer.render(timer)}

  defp render_core(_resource, _context), do: :ignore
end
