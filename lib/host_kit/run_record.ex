defmodule HostKit.RunRecord do
  @moduledoc "Minimal host-side record of an applied HostKit plan."

  use JSONCodec, fast_path: :json

  alias HostKit.{Conventions, Plan, Resource, Runner}

  @version 1

  defmodule Change do
    @moduledoc "One compact change entry in a HostKit run record."

    use JSONCodec, fast_path: :json

    @type t :: %__MODULE__{
            resource_id: term(),
            action: String.t(),
            status: String.t(),
            reason: term()
          }

    defstruct resource_id: nil,
              action: nil,
              status: nil,
              reason: nil
  end

  @type t :: %__MODULE__{
          version: pos_integer(),
          id: String.t(),
          project: String.t(),
          direction: String.t(),
          applied_at: String.t(),
          changes: [Change.t()],
          artifacts: %{String.t() => String.t()},
          backups: %{String.t() => String.t()}
        }

  defstruct version: @version,
            id: nil,
            project: nil,
            direction: nil,
            applied_at: nil,
            changes: [],
            artifacts: %{},
            backups: %{}

  codec(:version, transform: :validate_version!)
  codec(:changes, type: {:list, Change})

  @spec write(Plan.t(), [HostKit.Apply.result()], keyword()) :: :ok | {:error, term()}
  def write(%Plan{} = plan, results, opts) do
    if Keyword.get(opts, :track, false) do
      id = run_id(plan)
      path = record_path(plan, opts, id)

      with {:ok, artifacts} <- write_artifacts(plan, id, opts),
           {:ok, backups} <- write_backups(plan, results, id, opts),
           :ok <- Runner.mkdir_p(runner(opts), Path.dirname(path), opts) do
        content =
          plan
          |> record(results, id, artifacts, backups)
          |> dump()
          |> Jason.encode_to_iodata!(pretty: true)

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
      {:ok, content} -> decode(content)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec apply_backups(Plan.t(), t()) :: Plan.t()
  def apply_backups(%Plan{} = plan, %__MODULE__{} = record) do
    backups = record.backups || %{}
    changes = Enum.map(plan.changes, &apply_change_backup(&1, backups))
    %Plan{plan | changes: changes}
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

  defp apply_change_backup(
         %HostKit.Change{resource_id: resource_id, before: %HostKit.Resources.File{} = file} =
           change,
         backups
       ) do
    case Map.get(backups, inspect(resource_id)) do
      path when is_binary(path) ->
        %HostKit.Change{
          change
          | before: %HostKit.Resources.File{file | content: %HostKit.BackupRef{path: path}}
        }

      _missing ->
        change
    end
  end

  defp apply_change_backup(change, _backups), do: change

  def validate_version!(@version), do: @version

  def validate_version!(version) do
    raise JSONCodec.Error,
      path: [:version],
      expected: @version,
      got: version,
      reason: :unsupported_run_record_version
  end

  defp load_records(files, opts) do
    Enum.flat_map(files, fn path ->
      case load(Path.basename(path), opts) do
        {:ok, record} -> [record]
        {:error, _reason} -> []
      end
    end)
  end

  defp sort_records(records), do: Enum.sort_by(records, &(&1.applied_at || ""), :desc)

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

  defp record(%Plan{} = plan, results, id, artifacts, backups) do
    %__MODULE__{
      id: id,
      project: project_name(plan.project),
      direction: plan.opts |> Keyword.get(:direction, :up) |> to_string(),
      applied_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      changes: Enum.map(results, &change_record/1),
      artifacts: artifacts,
      backups: backups
    }
  end

  defp write_artifacts(plan, id, opts) do
    artifacts_root = Path.join([runs_root(plan, opts), "artifacts", id])

    %{}
    |> maybe_write_artifact("up_plan", Keyword.get(opts, :up_plan_artifact), artifacts_root, opts)
    |> maybe_write_artifact(
      "down_plan",
      Keyword.get(opts, :down_plan_artifact),
      artifacts_root,
      opts
    )
  end

  defp maybe_write_artifact({:error, reason}, _key, _source, _root, _opts), do: {:error, reason}

  defp maybe_write_artifact({:ok, artifacts}, key, source, root, opts),
    do: maybe_write_artifact(artifacts, key, source, root, opts)

  defp maybe_write_artifact(artifacts, _key, nil, _root, _opts), do: {:ok, artifacts}

  defp maybe_write_artifact(artifacts, key, source, root, opts) do
    target = Path.join(root, Path.basename(source))

    with {:ok, content} <- File.read(source),
         :ok <- Runner.mkdir_p(runner(opts), root, opts),
         :ok <- Runner.write_file(runner(opts), target, content, opts) do
      {:ok, Map.put(artifacts, key, target)}
    end
  end

  defp write_backups(plan, results, id, opts) do
    root = Path.join([backups_root(plan, opts), id])

    Enum.reduce_while(results, {:ok, %{}}, &write_backup_step(&1, &2, root, opts))
  end

  defp write_backup_step(result, {:ok, backups}, root, opts) do
    case backup_content(result) do
      {:ok, resource_id, content} ->
        write_backup_content(backups, resource_id, content, root, opts)

      :skip ->
        {:cont, {:ok, backups}}
    end
  end

  defp write_backup_content(backups, resource_id, content, root, opts) do
    path = Path.join(root, backup_filename(resource_id))

    case write_backup(path, content, opts) do
      :ok -> {:cont, {:ok, Map.put(backups, inspect(resource_id), path)}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp backup_content(%{change: %{before: nil}}), do: :skip

  defp backup_content(%{
         change: %{resource_id: resource_id, before: %HostKit.Resources.File{content: content}}
       })
       when is_binary(content), do: {:ok, resource_id, content}

  defp backup_content(%{
         change: %{resource_id: resource_id, before: %{meta: %{content: content}}}
       })
       when is_binary(content), do: {:ok, resource_id, content}

  defp backup_content(_result), do: :skip

  defp write_backup(path, content, opts) do
    with :ok <- Runner.mkdir_p(runner(opts), Path.dirname(path), opts) do
      Runner.write_file(runner(opts), path, content, opts)
    end
  end

  defp backup_filename(resource_id) do
    resource_id
    |> inspect()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_.-]+/, "-")
    |> String.trim("-.")
    |> Kernel.<>(".bak")
  end

  defp backups_root(plan, opts) do
    opts
    |> Keyword.get(:hostkit_backups_root)
    |> case do
      nil -> plan |> plan_project() |> project_conventions() |> Conventions.backups_root()
      root -> root
    end
  end

  defp change_record(%{change: change, status: status}) do
    %Change{
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
  defp project_conventions(%{conventions: conventions}), do: Conventions.new(conventions)
  defp runner(opts), do: Keyword.get(opts, :runner, HostKit.Runner.Local)
end
