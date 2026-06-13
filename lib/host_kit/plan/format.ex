defmodule HostKit.Plan.Format do
  @moduledoc "Human-readable plan formatting."

  alias HostKit.Addr.Resource
  alias HostKit.{Change, Plan}
  alias HostKit.Package.Resolution

  @action_marks %{create: "+", update: "~", delete: "-", no_op: "=", read: "?"}

  @spec format(Plan.t()) :: String.t()
  def format(%Plan{} = plan) do
    [summary(plan), "\n", changes(plan.changes)]
    |> IO.iodata_to_binary()
    |> String.trim_trailing()
  end

  @spec format_change(Change.t()) :: String.t()
  def format_change(%Change{} = change) do
    mark = Map.get(@action_marks, change.action, "?")

    [
      mark,
      " ",
      format_resource_id(change.resource_id),
      "\n  ",
      Atom.to_string(change.action),
      " ",
      format_reason(change.reason),
      format_details(change)
    ]
    |> IO.iodata_to_binary()
  end

  defp summary(%Plan{changes: changes}) do
    counts = Enum.frequencies_by(changes, & &1.action)

    [
      "Plan: ",
      count(counts, :create, "to create"),
      ", ",
      count(counts, :update, "to update"),
      ", ",
      count(counts, :delete, "to delete"),
      ", ",
      count(counts, :read, "read errors"),
      ", ",
      count(counts, :no_op, "unchanged")
    ]
  end

  defp count(counts, action, label), do: "#{Map.get(counts, action, 0)} #{label}"

  defp changes(changes) do
    changes
    |> Enum.map(&format_change/1)
    |> Enum.intersperse("\n")
  end

  defp format_details(%Change{after: %{meta: %{resolution: %Resolution{} = resolution}}}) do
    [
      "\n  resolves to ",
      resolution.package,
      " via ",
      Atom.to_string(resolution.source),
      resolution_context(resolution)
    ]
  end

  defp format_details(_change), do: []

  defp resolution_context(%Resolution{project: project, repo: repo}) do
    case {project, repo} do
      {nil, nil} -> ""
      {project, nil} -> " (#{project})"
      {nil, repo} -> " (#{repo})"
      {project, repo} -> " (#{project}/#{repo})"
    end
  end

  defp format_resource_id(%Resource{} = resource), do: to_string(resource)
  defp format_resource_id({type, name}), do: "#{type}.#{name}"
  defp format_resource_id(resource_id), do: inspect(resource_id)

  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)
end
