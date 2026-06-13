defmodule HostKit.Monitor do
  @moduledoc "Helpers for extracting monitoring declarations from HostKit projects."

  alias HostKit.Monitor.Check
  alias HostKit.Project

  @spec check(atom(), keyword()) :: Check.t()
  def check(type, opts) when is_atom(type) do
    %Check{
      type: type,
      name: Keyword.get(opts, :name),
      target: Keyword.get(opts, :target, Keyword.get(opts, :url, Keyword.get(opts, :unit))),
      expect: Keyword.get(opts, :expect, []),
      severity: Keyword.get(opts, :severity, :warning),
      resource_id: Keyword.get(opts, :resource_id),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @spec checks(Project.t()) :: [Check.t()]
  def checks(%Project{} = project) do
    project
    |> Project.resources()
    |> Enum.flat_map(&resource_checks/1)
  end

  defp resource_checks(resource) do
    resource
    |> Map.get(:meta, %{})
    |> Map.get(:monitor, [])
    |> List.wrap()
  end
end
