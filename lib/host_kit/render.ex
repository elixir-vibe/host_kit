defmodule HostKit.Render do
  @moduledoc "Renders resources through core renderers and optional plugin renderers."

  alias HostKit.Addr
  alias HostKit.{Project, Provider, Resource}

  @spec render(Project.t(), term(), map()) :: {:ok, iodata()} | {:error, term()}
  def render(%Project{} = project, resource_id, context \\ %{}) do
    with {:ok, resource} <- find_resource(project, resource_id) do
      render_resource(project, resource, context)
    end
  end

  @spec render_resource(Project.t(), struct(), map()) :: {:ok, iodata()} | {:error, term()}
  def render_resource(%Project{} = project, resource, context \\ %{}) do
    case render_core(resource, context) do
      :ignore -> Provider.render(project.providers, resource, context)
      result -> result
    end
  end

  @spec find_resource(Project.t(), term()) :: {:ok, struct()} | {:error, :not_found}
  def find_resource(%Project{} = project, resource_id) do
    case Enum.find(Project.resources(project), &id_matches?(&1, resource_id)) do
      nil -> {:error, :not_found}
      resource -> {:ok, resource}
    end
  end

  defp render_core(%HostKit.Systemd.Service{} = service, _context),
    do: {:ok, HostKit.Systemd.Service.render(service)}

  defp render_core(%HostKit.Systemd.Timer{} = timer, _context),
    do: {:ok, HostKit.Systemd.Timer.render(timer)}

  defp render_core(_resource, _context), do: :ignore

  defp id_matches?(resource, resource_id) do
    id = Resource.id(resource)
    normalized = tuple_to_resource_addr(resource_id)

    id == resource_id or id == normalized or same_resource_addr?(id, normalized)
  end

  defp tuple_to_resource_addr({type, name}) when is_atom(type), do: Addr.Resource.new(type, name)
  defp tuple_to_resource_addr(resource_id), do: resource_id

  defp same_resource_addr?(%Addr.Resource{} = left, %Addr.Resource{} = right) do
    left.mode == right.mode and left.type == right.type and
      to_string(left.name) == to_string(right.name)
  end

  defp same_resource_addr?(_left, _right), do: false
end
