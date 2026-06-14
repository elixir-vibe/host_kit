defmodule HostKit.RunRecord do
  @moduledoc "Minimal host-side record of an applied HostKit plan."

  alias HostKit.{Conventions, Plan, Resource, Runner}

  @version 1

  @spec write(Plan.t(), [HostKit.Apply.result()], keyword()) :: :ok | {:error, term()}
  def write(%Plan{} = plan, results, opts) do
    if Keyword.get(opts, :track, false) do
      id = run_id(plan)
      path = record_path(plan, opts, id)
      content = Jason.encode_to_iodata!(record(plan, results, id), pretty: true)

      with :ok <- Runner.mkdir_p(runner(opts), Path.dirname(path), opts) do
        Runner.write_file(runner(opts), path, content, opts)
      end
    else
      :ok
    end
  end

  defp record(%Plan{} = plan, results, id) do
    %{
      version: @version,
      id: id,
      project: plan.project && to_string(plan.project.name),
      direction: plan.opts |> Keyword.get(:direction, :up) |> to_string(),
      applied_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      changes: Enum.map(results, &change_record/1)
    }
  end

  defp change_record(%{change: change, status: status}) do
    %{
      resource_id: Resource.dump(change.resource_id),
      action: to_string(change.action),
      status: to_string(status),
      reason: Resource.dump(change.reason)
    }
  end

  defp record_path(plan, opts, id) do
    runs_root =
      opts
      |> Keyword.get(:hostkit_runs_root)
      |> case do
        nil -> plan.project |> project_conventions() |> Conventions.runs_root()
        root -> root
      end

    Path.join(runs_root, id <> ".json")
  end

  defp run_id(plan) do
    stamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d-%H%M%S")
    project = if plan.project && plan.project.name, do: to_string(plan.project.name), else: "plan"
    direction = plan.opts |> Keyword.get(:direction, :up) |> to_string()
    "#{stamp}-#{project}-#{direction}"
  end

  defp project_conventions(nil), do: Conventions.new()
  defp project_conventions(project), do: project.conventions
  defp runner(opts), do: Keyword.get(opts, :runner, HostKit.Runner.Local)
end
