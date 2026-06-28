defmodule HostKit.Clean do
  @moduledoc "Builds conservative cleanup plans from existing HostKit release metadata."

  alias HostKit.{Change, Plan, Project, Runner}
  alias HostKit.Resources.Command

  @type release_meta :: map()

  @spec plan(Project.t(), keyword()) :: {:ok, Plan.t()} | {:error, term()}
  def plan(%Project{} = project, opts \\ []) do
    with {:ok, services} <- Project.resolve_services(project, Keyword.get(opts, :services)),
         {:ok, commands} <- cleanup_commands(project, services, opts) do
      changes =
        Enum.map(commands, fn command ->
          %Change{
            action: :create,
            resource_id: HostKit.Resource.id(command),
            before: nil,
            after: command,
            reason: :cleanup
          }
        end)

      {:ok,
       %Plan{
         project: project,
         resources: commands,
         changes: changes,
         opts: opts,
         summary: %{direction: :clean}
       }}
    end
  end

  defp cleanup_commands(%Project{} = project, services, opts) do
    project.services
    |> select_services(services)
    |> Enum.flat_map(&service_releases/1)
    |> Enum.reduce_while({:ok, []}, fn release, {:ok, commands} ->
      case release_commands(release, opts) do
        {:ok, release_commands} -> {:cont, {:ok, commands ++ release_commands}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp select_services(services, nil), do: services

  defp select_services(services, selected) do
    selected = MapSet.new(selected)
    Enum.filter(services, &MapSet.member?(selected, &1.name))
  end

  defp service_releases(service) do
    service.meta
    |> Map.get(:releases, %{})
    |> Map.values()
    |> Enum.map(&Map.put_new(&1, :service, service.name))
  end

  defp release_commands(release, opts) do
    keep = keep_count(release, opts)

    with {:ok, active_path} <- active_release_path(release, opts),
         {:ok, release_entries} <- list_release_dirs(release, opts),
         {:ok, artifact_entries} <- list_artifacts(release, opts) do
      active_version = Path.basename(active_path)

      stale_versions = stale_versions(release_entries, active_version, keep)
      stale_release_paths = paths_for_versions(release_entries, stale_versions)
      stale_artifact_paths = artifact_paths_for_versions(artifact_entries, stale_versions)

      commands =
        stale_release_paths
        |> Enum.map(&rm_command(release, :release, &1))
        |> Kernel.++(Enum.map(stale_artifact_paths, &rm_command(release, :artifact, &1)))

      {:ok, commands}
    end
  end

  defp keep_count(release, opts) do
    keep = Keyword.get(opts, :keep) || Map.get(release, :keep) || 2
    max(keep, 1)
  end

  defp active_release_path(
         %{current_path: current_path, releases_dir: releases_dir} = release,
         opts
       ) do
    script = "if [ -L \"$1\" ]; then readlink -f \"$1\"; fi"

    case cmd_output(opts, "sh", ["-c", script, "sh", current_path]) do
      {:ok, ""} ->
        {:error, {:active_release_not_found, release_name(release), current_path}}

      {:ok, active_path} ->
        active_path = String.trim(active_path)

        if under_dir?(active_path, releases_dir) do
          {:ok, active_path}
        else
          {:error,
           {:active_release_outside_releases_dir, release_name(release), active_path,
            releases_dir}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_release_dirs(%{releases_dir: releases_dir}, opts) do
    script =
      "if [ -d \"$1\" ]; then find \"$1\" -mindepth 1 -maxdepth 1 -type d -printf '%f\\t%p\\n' | sort; fi"

    with {:ok, output} <- cmd_output(opts, "sh", ["-c", script, "sh", releases_dir]) do
      {:ok, parse_tabbed_paths(output)}
    end
  end

  defp list_artifacts(%{artifact_dir: artifact_dir, artifact_prefix: prefix}, opts)
       when is_binary(artifact_dir) and is_binary(prefix) do
    script =
      "if [ -d \"$1\" ]; then find \"$1\" -maxdepth 1 -type f \\( -name \"$2-*.tar.gz\" -o -name \"$2-*.tar.gz.sha256\" \\) -printf '%f\\t%p\\n' | sort; fi"

    with {:ok, output} <- cmd_output(opts, "sh", ["-c", script, "sh", artifact_dir, prefix]) do
      {:ok, parse_tabbed_paths(output)}
    end
  end

  defp list_artifacts(_release, _opts), do: {:ok, []}

  defp parse_tabbed_paths(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, "\t", parts: 2) do
        [name, path] -> [{name, path}]
        _other -> []
      end
    end)
  end

  defp stale_versions(entries, active_version, keep) do
    entries
    |> Enum.map(fn {version, _path} -> version end)
    |> Enum.reject(&(&1 == active_version))
    |> Enum.sort(:desc)
    |> Enum.drop(max(keep - 1, 0))
    |> MapSet.new()
  end

  defp paths_for_versions(entries, versions) do
    entries
    |> Enum.filter(fn {version, _path} -> MapSet.member?(versions, version) end)
    |> Enum.map(fn {_version, path} -> path end)
  end

  defp artifact_paths_for_versions(entries, versions) do
    versions
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.flat_map(fn version ->
      Enum.flat_map(entries, fn {name, path} ->
        if artifact_for_version?(name, version), do: [path], else: []
      end)
    end)
  end

  defp artifact_for_version?(name, version) do
    String.ends_with?(name, "-#{version}.tar.gz") or
      String.ends_with?(name, "-#{version}.tar.gz.sha256")
  end

  defp rm_command(release, kind, path) do
    %Command{
      name: command_name(release, kind, path),
      exec: {"rm", ["-rf", path]},
      down: :irreversible,
      meta: %{cleanup: :release_retention, release: release_name(release), path: path}
    }
  end

  defp command_name(release, kind, path) do
    ["clean", release_name(release), kind, Path.basename(path)]
    |> Enum.map_join("_", &safe_name/1)
  end

  defp safe_name(value) do
    value
    |> to_string()
    |> String.replace(~r/[^A-Za-z0-9_]+/, "_")
    |> String.trim("_")
  end

  defp release_name(%{name: name}), do: name
  defp release_name(%{service: service}), do: service
  defp release_name(_release), do: :release

  defp under_dir?(path, dir) do
    path = Path.expand(path)
    dir = Path.expand(dir)
    path == dir or String.starts_with?(path, dir <> "/")
  end

  defp cmd_output(opts, command, args) do
    {command, args} = maybe_sudo(command, args, opts)
    runner = Keyword.get(opts, :runner, HostKit.Runner.Local)

    case Runner.cmd(runner, command, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim_trailing(output)}
      {output, status} -> {:error, {:command_failed, command, args, status, output}}
    end
  end

  defp maybe_sudo(command, args, opts) do
    if Keyword.get(opts, :sudo, false), do: {"sudo", [command | args]}, else: {command, args}
  end
end
