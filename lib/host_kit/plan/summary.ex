defmodule HostKit.Plan.Summary do
  @moduledoc "Shared summaries for plans, audits, reads, and plan artifacts."

  alias HostKit.{Change, Plan, Resource}

  @changing_actions [:create, :update, :delete]
  @known_actions [:create, :update, :delete, :read, :no_op]

  @spec action_counts([Change.t()] | Plan.t()) :: map()
  def action_counts(%Plan{changes: changes}), do: action_counts(changes)

  def action_counts(changes) when is_list(changes) do
    changes
    |> Enum.frequencies_by(& &1.action)
    |> stringify_keys(@known_actions)
  end

  @spec resource_counts([struct()] | Plan.t()) :: map()
  def resource_counts(%Plan{resources: resources}), do: resource_counts(resources)

  def resource_counts(resources) when is_list(resources) do
    resources
    |> Enum.frequencies_by(&resource_count_type/1)
    |> sort_map()
  end

  @spec change_counts_by_type([Change.t()] | Plan.t()) :: map()
  def change_counts_by_type(%Plan{changes: changes}), do: change_counts_by_type(changes)

  def change_counts_by_type(changes) when is_list(changes) do
    changes
    |> Enum.group_by(&resource_id_type/1)
    |> Map.new(fn {type, changes} -> {type, action_counts(changes)} end)
    |> sort_map()
  end

  @spec drift_count([Change.t()] | Plan.t()) :: non_neg_integer()
  def drift_count(%Plan{changes: changes}), do: drift_count(changes)

  def drift_count(changes) when is_list(changes) do
    Enum.count(changes, &(&1.action in @changing_actions))
  end

  @spec drift_counts_by_type([Change.t()] | Plan.t()) :: map()
  def drift_counts_by_type(%Plan{changes: changes}), do: drift_counts_by_type(changes)

  def drift_counts_by_type(changes) when is_list(changes) do
    changes
    |> Enum.filter(&(&1.action in @changing_actions))
    |> Enum.frequencies_by(&resource_id_type/1)
    |> sort_map()
  end

  @spec redacted_config_paths([struct()] | Plan.t()) :: [map()]
  def redacted_config_paths(%Plan{resources: resources}), do: redacted_config_paths(resources)

  def redacted_config_paths(resources) when is_list(resources) do
    resources
    |> Enum.flat_map(fn
      %HostKit.Resources.ConfigFile{} = config ->
        paths = HostKit.Resources.ConfigFile.secret_paths(config)

        if paths == [] do
          []
        else
          [%{resource_id: Resource.dump(HostKit.Resources.ConfigFile.id(config)), paths: paths}]
        end

      _resource ->
        []
    end)
  end

  @spec redacted_config_count([struct()] | Plan.t()) :: non_neg_integer()
  def redacted_config_count(plan_or_resources) do
    plan_or_resources
    |> redacted_config_paths()
    |> Enum.sum_by(&length(&1.paths))
  end

  @spec artifact_stats(Plan.t()) :: map()
  def artifact_stats(%Plan{} = plan) do
    %{
      "actions" => action_counts(plan),
      "resources" => resource_counts(plan),
      "changes_by_type" => change_counts_by_type(plan),
      "drift_by_type" => drift_counts_by_type(plan),
      "redacted_config_entries" => redacted_config_count(plan)
    }
    |> maybe_put_down_plan(plan)
  end

  defp maybe_put_down_plan(stats, %Plan{summary: %{direction: :down}} = plan),
    do: Map.put(stats, "down_plan", down_report(plan))

  defp maybe_put_down_plan(stats, _plan), do: stats

  @spec down_report(Plan.t()) :: map()
  def down_report(%Plan{} = plan) do
    source_total = get_in(plan.summary, [:down, :source_changes]) || length(plan.changes)
    skipped = irreversible_warnings(plan.diagnostics)
    reversible = length(plan.changes)
    noop = get_in(plan.summary, [:down, :noop]) || 0

    %{
      source_changes: source_total,
      reversible_changes: reversible,
      noop_changes: noop,
      skipped_changes: length(skipped),
      reversible_percent: percent(reversible + noop, source_total),
      skipped_by_reason: skipped_by_reason(skipped),
      skipped_by_type: skipped_by_type(skipped)
    }
  end

  @spec irreversible_warnings(HostKit.Diagnostics.t()) :: [HostKit.Diagnostic.t()]
  def irreversible_warnings(%HostKit.Diagnostics{} = diagnostics) do
    Enum.filter(diagnostics.warnings, &(&1.code == :irreversible_change))
  end

  @spec audit_report(Plan.t()) :: map()
  def audit_report(%Plan{} = plan) do
    counts = action_counts(plan)

    %{
      managed_resources: length(plan.resources),
      resources_by_type: resource_counts(plan),
      drift: drift_count(plan),
      drift_by_type: drift_counts_by_type(plan),
      read_errors: Map.fetch!(counts, "read"),
      unchanged: Map.fetch!(counts, "no_op"),
      actions: counts,
      changes_by_type: change_counts_by_type(plan),
      redacted_config_entries: redacted_config_count(plan),
      redacted_config_paths: redacted_config_paths(plan)
    }
  end

  def resource_count_type(resource) when is_map(resource) do
    resource |> Resource.id() |> resource_id_name()
  rescue
    _error in [ArgumentError, KeyError, UndefinedFunctionError] -> resource_type(resource)
  end

  def resource_count_type(resource), do: resource_type(resource)

  def resource_type(%module{}), do: resource_type(module)

  def resource_type(module) when is_atom(module) do
    module |> Module.split() |> List.last() |> Macro.underscore()
  end

  def resource_type(resource) when is_map_key(resource, :__struct__),
    do: resource.__struct__ |> resource_type()

  def resource_type(_resource), do: "unknown"

  def resource_id_type(%Change{
        resource_id: resource_id,
        after: after_resource,
        before: before_resource
      }) do
    cond do
      not is_nil(resource_id) -> resource_id_name(resource_id)
      not is_nil(after_resource) -> resource_count_type(after_resource)
      not is_nil(before_resource) -> resource_count_type(before_resource)
      true -> "unknown"
    end
  end

  def resource_id_type(_change), do: "unknown"

  defp resource_id_name({type, _name}), do: to_string(type)
  defp resource_id_name(%HostKit.Addr.Resource{type: type}), do: to_string(type)
  defp resource_id_name(_resource_id), do: "unknown"

  defp skipped_by_reason(warnings) do
    warnings
    |> Enum.frequencies_by(&to_string(&1.details.reason))
    |> sort_map()
  end

  defp skipped_by_type(warnings) do
    warnings
    |> Enum.frequencies_by(&warning_resource_type/1)
    |> sort_map()
  end

  defp warning_resource_type(%{resource_id: resource_id}), do: resource_id_name(resource_id)
  defp warning_resource_type(_warning), do: "unknown"

  defp percent(_covered, 0), do: 100
  defp percent(covered, total), do: Float.round(covered * 100 / total, 1)

  defp stringify_keys(counts, keys) do
    keys
    |> Map.new(fn action -> {to_string(action), Map.get(counts, action, 0)} end)
    |> Map.merge(
      counts
      |> Enum.reject(fn {action, _count} -> action in keys end)
      |> Map.new(fn {action, count} -> {to_string(action), count} end)
    )
  end

  defp sort_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Map.new()
  end
end
