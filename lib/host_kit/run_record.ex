defmodule HostKit.RunRecord do
  @moduledoc "Minimal host-side record of an applied HostKit plan."

  alias HostKit.{Conventions, Plan, Resource, Runner}

  @version 1

  @type t :: map()

  @spec write(Plan.t(), [HostKit.Apply.result()], keyword()) :: :ok | {:error, term()}
  def write(%Plan{} = plan, results, opts) do
    if Keyword.get(opts, :track, false) do
      id = run_id(plan)
      path = record_path(plan, opts, id)
      content = Jason.encode_to_iodata!(record(plan, results, id, opts), pretty: true)

      with :ok <- Runner.mkdir_p(runner(opts), Path.dirname(path), opts) do
        Runner.write_file(runner(opts), path, content, opts)
      end
    else
      :ok
    end
  end

  @spec list(keyword()) :: {:ok, [t()]} | {:error, term()}
  def list(opts \\ []) do
    case list_files(opts) do
      {:ok, files} -> {:ok, files |> load_records(opts) |> sort_records()}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec latest(keyword()) :: {:ok, t()} | {:error, term()}
  def latest(opts \\ []) do
    case list(opts) do
      {:ok, [record | _]} -> {:ok, record}
      {:ok, []} -> {:error, :no_run_records}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec load(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def load(id_or_file, opts \\ []) do
    id_or_file
    |> run_path(opts)
    |> read_text(opts)
    |> case do
      {:ok, content} -> Jason.decode(content)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec runs_root(Plan.t() | nil, keyword()) :: String.t()
  def runs_root(plan \\ nil, opts) do
    opts
    |> Keyword.get(:hostkit_runs_root)
    |> case do
      nil -> plan |> plan_project() |> project_conventions() |> Conventions.runs_root()
      root -> root
    end
  end

  defp load_records(files, opts) do
    Enum.flat_map(files, fn path ->
      case load(Path.basename(path), opts) do
        {:ok, record} -> [record]
        {:error, _reason} -> []
      end
    end)
  end

  defp sort_records(records), do: Enum.sort_by(records, &Map.get(&1, "applied_at", ""), :desc)

  defp list_files(opts) do
    root = runs_root(nil, opts)

    case runner(opts) do
      HostKit.Runner.Local ->
        {:ok, Path.wildcard(Path.join(root, "*.json"))}

      runner ->
        script = "ls -1 #{HostKit.Shell.escape(root)}/*.json 2>/dev/null || true"

        case Runner.cmd(runner, "sh", ["-c", script], stderr_to_stdout: true) do
          {output, 0} -> {:ok, output |> String.split("\n", trim: true)}
          {output, status} -> {:error, {:command_failed, "ls", status, output}}
        end
    end
  end

  defp read_text(path, opts) do
    case runner(opts) do
      HostKit.Runner.Local ->
        File.read(path)

      runner ->
        case Runner.cmd(runner, "sh", ["-c", "cat #{HostKit.Shell.escape(path)}"],
               stderr_to_stdout: true
             ) do
          {output, 0} -> {:ok, output}
          {output, status} -> {:error, {:command_failed, "cat", status, output}}
        end
    end
  end

  defp run_path(id_or_file, opts) do
    if String.ends_with?(id_or_file, ".json") and String.contains?(id_or_file, "/") do
      id_or_file
    else
      file =
        if String.ends_with?(id_or_file, ".json"), do: id_or_file, else: id_or_file <> ".json"

      Path.join(runs_root(nil, opts), file)
    end
  end

  defp record(%Plan{} = plan, results, id, opts) do
    %{
      version: @version,
      id: id,
      project: project_name(plan.project),
      direction: plan.opts |> Keyword.get(:direction, :up) |> to_string(),
      applied_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      changes: Enum.map(results, &change_record/1),
      artifacts: artifacts(opts)
    }
  end

  defp artifacts(opts) do
    %{}
    |> put_artifact("up_plan", Keyword.get(opts, :up_plan_artifact))
    |> put_artifact("down_plan", Keyword.get(opts, :down_plan_artifact))
  end

  defp put_artifact(artifacts, _key, nil), do: artifacts
  defp put_artifact(artifacts, key, path), do: Map.put(artifacts, key, path)

  defp change_record(%{change: change, status: status}) do
    %{
      resource_id: Resource.dump(change.resource_id),
      action: to_string(change.action),
      status: to_string(status),
      reason: Resource.dump(change.reason)
    }
  end

  defp record_path(plan, opts, id), do: Path.join(runs_root(plan, opts), id <> ".json")

  defp run_id(plan) do
    stamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d-%H%M%S")
    project = if plan.project && plan.project.name, do: to_string(plan.project.name), else: "plan"
    direction = plan.opts |> Keyword.get(:direction, :up) |> to_string()
    "#{stamp}-#{project}-#{direction}"
  end

  defp project_name(project), do: to_string(project.name)

  defp plan_project(%Plan{project: project}), do: project
  defp plan_project(nil), do: nil
  defp project_conventions(nil), do: Conventions.new()
  defp project_conventions(project), do: project.conventions
  defp runner(opts), do: Keyword.get(opts, :runner, HostKit.Runner.Local)
end
