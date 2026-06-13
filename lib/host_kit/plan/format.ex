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

  defp format_details(%Change{after: %HostKit.Resources.Command{} = command}) do
    [
      "\n  exec: ",
      format_exec(command.exec),
      format_runtime(command.runtime),
      format_paths("inputs", command.inputs),
      format_paths("outputs", command.outputs),
      format_stamp(command)
    ]
  end

  defp format_details(%Change{after: %HostKit.Resources.Shell{} = shell}) do
    [
      "\n  bash commands: ",
      Enum.map_join(shell.script.commands, ", ", & &1.name),
      format_paths("inputs", shell.inputs),
      format_paths("outputs", shell.outputs),
      format_stamp(shell)
    ]
  end

  defp format_details(%Change{after: %HostKit.Resources.Source{} = source}) do
    [
      "\n  type: ",
      Atom.to_string(source.type),
      "\n  uri: ",
      source.uri,
      "\n  ref: ",
      source.ref,
      " (",
      Atom.to_string(source.ref_kind),
      ")",
      format_source_revision(source.revision),
      format_mutable_source(source),
      "\n  checkout: ",
      source.checkout,
      format_source_path(source.path)
    ]
  end

  defp format_details(%Change{after: %{meta: %{resolution: %Resolution{} = resolution}}}) do
    [
      "\n  resolves to ",
      resolution.package,
      " via ",
      format_resolution_source(resolution.source),
      resolution_context(resolution)
    ]
  end

  defp format_details(_change), do: []

  defp format_exec({command, args}), do: Enum.join([command | args], " ")

  defp format_source_revision(nil), do: []
  defp format_source_revision(revision), do: ["\n  resolved: ", revision]

  defp format_mutable_source(%{ref_kind: :branch}),
    do: ["\n  warning: mutable ref; resolved revision is pinned in this plan"]

  defp format_mutable_source(_source), do: []

  defp format_source_path("."), do: []
  defp format_source_path(path), do: ["\n  path: ", path]

  defp format_runtime(nil), do: []
  defp format_runtime({kind, name}), do: ["\n  runtime: ", to_string(kind), ".", to_string(name)]

  defp format_paths(_label, []), do: []
  defp format_paths(label, paths), do: ["\n  ", label, ": ", Enum.join(paths, ", ")]

  defp format_stamp(resource) do
    if HostKit.RunStamp.stamp_required?(resource) do
      ["\n  stamp: ", HostKit.RunStamp.stamp_path(resource)]
    else
      []
    end
  end

  defp format_resolution_source(:repology_api), do: "repology api"
  defp format_resolution_source(:repology_cache), do: "repology cache"
  defp format_resolution_source(:repology_stale_cache), do: "stale repology cache"
  defp format_resolution_source(source) when is_atom(source), do: Atom.to_string(source)

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
