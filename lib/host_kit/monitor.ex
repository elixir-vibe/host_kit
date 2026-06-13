defmodule HostKit.Monitor do
  @moduledoc "Helpers for extracting monitoring declarations from HostKit projects."

  alias HostKit.Monitor.Check
  alias HostKit.Project

  @spec check(atom(), keyword()) :: Check.t()
  def check(type, opts) when is_atom(type) do
    opts
    |> Keyword.put(:type, type)
    |> Keyword.put_new(:target, Keyword.get(opts, :url, Keyword.get(opts, :unit)))
    |> Check.new()
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
