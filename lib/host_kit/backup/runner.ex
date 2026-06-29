defmodule HostKit.Backup.Runner do
  @moduledoc "Runs HostKit backup jobs from existing job/service metadata."

  alias HostKit.Backup.{Archive, Checksum, Job, Manifest, Retention, Service, Systemd}
  alias HostKit.Storage
  alias HostKit.Systemd.Service, as: SystemdService

  @spec run(HostKit.Project.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(project, job_name, opts \\ []) do
    with {:ok, job} <- fetch_job(project, job_name) do
      do_run(project, job, opts)
    end
  end

  defp do_run(project, %Job{} = job, opts) do
    stamp = Keyword.get_lazy(opts, :stamp, &stamp/0)
    File.mkdir_p!(job.destination)
    File.chmod!(job.destination, 0o700)

    state = %{project: to_string(project.name), job: job.name, stamp: stamp, archives: []}

    with {:ok, state} <- run_includes(project, job, state, opts) do
      manifest_path = Manifest.write!(job.destination, state)
      pruned = Retention.prune!(job.destination, job.keep)
      {:ok, Map.merge(state, %{manifest: manifest_path, pruned: pruned})}
    end
  end

  defp run_includes(project, job, state, opts) do
    Enum.reduce_while(job.includes, {:ok, state}, fn include, {:ok, state} ->
      case run_include(project, job, include, state, opts) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp run_include(project, job, {:service, service_name}, state, opts) do
    with {:ok, service} <- fetch_service(project, service_name),
         {:ok, archive} <- backup_service(project, job, service, state.stamp, opts) do
      {:ok, add_archive(state, archive)}
    end
  end

  defp run_include(_project, job, {:path, path}, state, opts) do
    name = archive_name(path)
    backup_paths(job, name, [path], state, opts)
  end

  defp run_include(_project, job, {:paths, name, paths}, state, opts) do
    backup_paths(job, name |> to_string() |> String.replace("_", "-"), paths, state, opts)
  end

  defp backup_paths(job, name, paths, state, opts) do
    archive = archive_path(job.destination, name, state.stamp)
    members = Enum.map(paths, &relative_path!/1)

    with :ok <- Archive.create(archive, members, opts),
         checksum <- Checksum.write_sha256!(archive) do
      {:ok,
       add_archive(state, %{
         name: name,
         kind: :path,
         path: archive,
         checksum: checksum,
         members: members
       })}
    end
  end

  defp backup_service(project, job, service, stamp, opts) do
    backup = Map.get(service.meta, :backup, %Service{})
    members = backup_paths!(service)
    unit = service_unit(project, service)
    archive = archive_path(job.destination, service.identity, stamp)

    with {:ok, was_active} <- maybe_stop(unit, backup.consistency, opts) do
      result = service_archive_result(archive, service, unit, backup, members, opts)
      restart_result = maybe_restart(unit, was_active, opts)

      case {result, restart_result} do
        {{:ok, archive_info}, :ok} -> {:ok, archive_info}
        {{:error, reason}, :ok} -> {:error, reason}
        {_result, {:error, reason}} -> {:error, reason}
      end
    end
  end

  defp service_archive_result(archive, service, unit, backup, members, opts) do
    with :ok <- create_verify_service_archive(archive, members, backup.verify, opts) do
      checksum = Checksum.write_sha256!(archive)

      {:ok,
       %{
         name: service.identity,
         kind: :service,
         service: to_string(service.name),
         unit: unit,
         consistency: backup.consistency,
         path: archive,
         checksum: checksum,
         members: members,
         verified: Enum.map(backup.verify, &relative_path!/1)
       }}
    end
  end

  defp create_verify_service_archive(archive, members, verify, opts) do
    with :ok <- Archive.create(archive, members, opts) do
      verify_archive(archive, verify, opts)
    end
  end

  defp maybe_stop(_unit, :online, _opts), do: {:ok, false}

  defp maybe_stop(unit, :stop, opts) do
    if Systemd.active?(unit, opts) do
      with :ok <- Systemd.stop(unit, opts), do: {:ok, true}
    else
      {:ok, false}
    end
  end

  defp maybe_restart(_unit, false, _opts), do: :ok

  defp maybe_restart(unit, true, opts) do
    with :ok <- Systemd.start(unit, opts), do: Systemd.wait_active(unit, opts)
  end

  defp verify_archive(_archive, [], _opts), do: :ok

  defp verify_archive(archive, verify, opts) do
    with {:ok, members} <- Archive.members(archive, opts) do
      member_set = MapSet.new(members)

      verify
      |> Enum.map(&relative_path!/1)
      |> Enum.find(&(not MapSet.member?(member_set, &1)))
      |> case do
        nil -> :ok
        missing -> {:error, {:archive_missing_member, archive, missing}}
      end
    end
  end

  defp fetch_job(project, job_name) do
    name = HostKit.DSL.Systemd.service_unit_name(job_name)

    project
    |> HostKit.Project.resources()
    |> Enum.find_value(fn
      %SystemdService{name: ^name, meta: %{backup: %Job{} = job}} -> job
      _resource -> nil
    end)
    |> case do
      %Job{} = job -> {:ok, job}
      nil -> {:error, {:unknown_backup_job, job_name}}
    end
  end

  defp fetch_service(project, name) do
    project.services
    |> Enum.find(&(&1.name == name))
    |> case do
      nil -> {:error, {:unknown_backup_service, name}}
      service -> {:ok, service}
    end
  end

  defp backup_paths!(service) do
    paths =
      service.meta
      |> Map.get(:storage, %{})
      |> Map.values()
      |> Enum.filter(&Storage.backup?/1)
      |> Enum.map(&relative_path!(&1.path))

    if paths == [] do
      raise ArgumentError,
            "service #{inspect(service.name)} has no storage volumes marked backup: true"
    end

    paths
  end

  defp service_unit(project, service) do
    project.conventions
    |> HostKit.Conventions.prefixed(:unit, service.identity)
    |> HostKit.Naming.systemd_unit()
  end

  defp add_archive(state, archive), do: %{state | archives: state.archives ++ [archive]}

  defp archive_path(destination, name, stamp),
    do: Path.join(destination, "#{name}-#{stamp}.tar.gz")

  defp archive_name(path) do
    path |> String.trim_leading("/") |> String.replace(~r/[^A-Za-z0-9_.-]+/, "-")
  end

  defp relative_path!("/" <> path), do: path

  defp relative_path!(path),
    do: raise(ArgumentError, "backup path must be absolute: #{inspect(path)}")

  defp stamp do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end
end
