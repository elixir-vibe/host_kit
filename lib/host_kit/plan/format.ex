defmodule HostKit.Plan.Format do
  @moduledoc "Human-readable plan formatting."

  alias HostKit.Addr.Resource
  alias HostKit.{Change, Plan}
  alias HostKit.Package.Resolution

  @action_marks %{create: "+", update: "~", delete: "-", no_op: "=", read: "?"}

  @spec format(Plan.t()) :: String.t()
  def format(%Plan{} = plan) do
    [
      diagnostics(plan.diagnostics),
      summary(plan),
      type_summary(plan),
      "\n",
      changes(plan.changes)
    ]
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

  defp diagnostics(%HostKit.Diagnostics{warnings: []}), do: []

  defp diagnostics(%HostKit.Diagnostics{} = diagnostics) do
    diagnostics.warnings
    |> Enum.map(&HostKit.Diagnostics.Format.format(%HostKit.Diagnostics{warnings: [&1]}))
    |> Enum.intersperse("\n")
    |> Kernel.++(["\n\n"])
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

  defp type_summary(%Plan{resources: []}), do: []

  defp type_summary(%Plan{} = plan) do
    [
      "\nResources: ",
      format_counts(HostKit.Plan.Summary.resource_counts(plan)),
      "\nChanges by type: ",
      format_change_counts(HostKit.Plan.Summary.change_counts_by_type(plan))
    ]
  end

  defp format_counts(counts) when map_size(counts) == 0, do: "none"

  defp format_counts(counts) do
    Enum.map_join(counts, ", ", fn {type, count} -> "#{type}=#{count}" end)
  end

  defp format_change_counts(counts) when map_size(counts) == 0, do: "none"

  defp format_change_counts(counts) do
    counts
    |> Enum.map_join(", ", fn {type, actions} ->
      active =
        actions
        |> Enum.reject(fn {_action, count} -> count == 0 end)
        |> Enum.map_join("/", fn {action, count} -> "#{action}=#{count}" end)

      "#{type}(#{active})"
    end)
  end

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

  defp format_details(%Change{after: %HostKit.Resources.Readiness{} = readiness}) do
    [
      "\n  checks: ",
      Enum.map_join(readiness.checks, ", ", &format_readiness_check/1),
      "\n  timeout: ",
      to_string(readiness.timeout),
      "ms"
    ]
  end

  defp format_details(%Change{after: %HostKit.Resources.ConfigFile{} = config_file} = change) do
    if HostKit.Resources.ConfigFile.secret?(config_file) do
      actual_entries = change.before && Map.get(change.before.meta, :actual_public_entries)

      changed_entries =
        HostKit.Resources.ConfigFile.changed_public_entries(config_file, actual_entries)

      secret_paths = HostKit.Resources.ConfigFile.secret_paths(config_file)

      [
        "\n  public keys: ",
        format_config_entries(changed_entries),
        "\n  redacted keys: ",
        format_config_paths(secret_paths)
      ]
    else
      []
    end
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

  defp format_readiness_check(%HostKit.Readiness.Systemd{
         unit: unit,
         state: state,
         restart: restart
       }) do
    restart = if restart, do: " restart", else: ""
    "systemd #{unit} #{state}#{restart}"
  end

  defp format_readiness_check(%HostKit.Readiness.HTTP{url: url, expect_body: nil}) do
    "http #{url}"
  end

  defp format_readiness_check(%HostKit.Readiness.HTTP{url: url, expect_body: body}) do
    "http #{url} contains #{inspect(body)}"
  end

  defp format_exec({command, args}), do: Enum.join([command | args], " ")

  defp format_source_revision(nil), do: []
  defp format_source_revision(revision), do: ["\n  resolved: ", revision]

  defp format_source_path("."), do: []
  defp format_source_path(path), do: ["\n  path: ", path]

  defp format_runtime(nil), do: []
  defp format_runtime({kind, name}), do: ["\n  runtime: ", to_string(kind), ".", to_string(name)]

  defp format_paths(_label, []), do: []

  defp format_paths(label, paths) do
    ["\n  ", label, ": ", Enum.map_join(paths, ", ", &format_path/1)]
  end

  defp format_config_entries([]), do: "none"

  defp format_config_entries(entries) do
    Enum.map_join(entries, ", ", fn entry ->
      "#{entry.path} #{inspect(entry.before)} -> #{inspect(entry.after)}"
    end)
  end

  defp format_config_paths([]), do: "none"
  defp format_config_paths(paths), do: Enum.join(paths, ", ")

  defp format_path(path) when is_binary(path), do: path
  defp format_path(path), do: inspect(path)

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
  defp format_reason(reason), do: HostKit.Error.format(reason)
end
