defmodule HostKit.Workspace do
  @moduledoc "Helpers for workspace-scoped metadata."

  alias HostKit.Project

  @spec inside_monitors(Project.t()) :: [map()]
  def inside_monitors(%Project{} = project) do
    project.services
    |> Enum.flat_map(fn service ->
      service.meta
      |> Map.get(:inside_monitor, [])
      |> Enum.map(&%{workspace: service.meta[:workspace], service: service.name, check: &1})
    end)
  end
end
