defmodule HostKit.Package.Resolver do
  @moduledoc "Resolves semantic package capabilities to concrete OS package names."

  alias HostKit.Package.Repology.Record
  alias HostKit.Package.Resolution
  alias HostKit.Package.TargetRepo
  alias HostKit.Resources.Capability
  alias HostKit.Resources.Package, as: PackageResource

  @callback resolve(PackageResource.t() | Capability.t(), keyword()) ::
              {:ok, PackageResource.t()} | {:error, term()}

  @manager_repos %{
    apt: ~r/^(debian|ubuntu)_/,
    dnf: ~r/^(fedora|centos|rocky|alma|rhel)_/,
    pacman: ~r/^(arch|archlinux)(_|$)/,
    apk: ~r/^alpine_/
  }

  @spec resolve(PackageResource.t() | Capability.t(), keyword()) ::
          {:ok, PackageResource.t()} | {:error, term()}
  def resolve(%Capability{} = capability, opts) do
    implementation = Keyword.get(opts, :package_resolver, __MODULE__)

    if implementation == __MODULE__ do
      resolve_candidate_packages(
        capability_package(capability),
        capability.name,
        capability.candidates,
        opts
      )
    else
      implementation.resolve(capability, opts)
    end
  end

  def resolve(%PackageResource{source: :explicit} = package, _opts), do: {:ok, package}

  def resolve(%PackageResource{} = package, opts) do
    implementation = Keyword.get(opts, :package_resolver, __MODULE__)

    if implementation == __MODULE__ do
      resolve_semantic(package, opts)
    else
      implementation.resolve(package, opts)
    end
  end

  defp resolve_semantic(%PackageResource{name: name} = package, opts) do
    capability = normalize_capability(name)

    if dev_capability?(capability) do
      resolve_development_package(package, capability, opts)
    else
      resolve_package_name(package, capability, opts)
    end
  end

  defp resolve_candidate_packages(package, capability, candidates, opts) do
    with {:ok, repo_match} <- repo_match(package, opts),
         :error <- locked_package(package, capability, repo_match, opts),
         {:ok, records} <- candidate_project_records(candidates, repo_match, opts),
         {:ok, resolution} <-
           select_preferred_package(records, capability, candidates, repo_match) do
      {:ok, apply_resolution(package, resolution)}
    end
  end

  defp resolve_development_package(package, capability, opts) do
    case repo_match(package, opts) do
      {:ok, repo_match} ->
        resolve_development_package(package, capability, repo_match, opts)

      {:error, _reason} ->
        {:ok, package}
    end
  end

  defp resolve_development_package(package, capability, repo_match, opts) do
    project = capability |> to_string() |> String.replace_suffix("_dev", "")

    with :error <- locked_package(package, capability, repo_match, opts),
         {:ok, records} <- package_project_records(project, repo_match, opts),
         {:ok, resolution} <- select_development_package(records, capability, project, repo_match) do
      {:ok, apply_resolution(package, resolution)}
    else
      {:error, {:http_error, 404, _body}} -> {:ok, package}
      {:error, :package_project_not_found} -> {:ok, package}
      {:error, {:package_resolution_not_found, _capability, _repo_match}} -> {:ok, package}
      error -> error
    end
  end

  defp candidate_project_records(candidates, repo_match, opts) do
    candidates
    |> Enum.reduce_while({:error, :package_project_not_found}, fn package_name, _error ->
      case package_project_records(package_name, repo_match, opts) do
        {:ok, records} -> {:halt, {:ok, records}}
        {:error, :package_project_not_found} -> {:cont, {:error, :package_project_not_found}}
        {:error, {:http_error, 404, _body}} -> {:cont, {:error, :package_project_not_found}}
        error -> {:halt, error}
      end
    end)
  end

  defp resolve_package_name(package, capability, opts) do
    case repo_match(package, opts) do
      {:ok, repo_match} ->
        resolve_package_name(package, capability, repo_match, opts)

      {:error, _reason} ->
        {:ok, package}
    end
  end

  defp resolve_package_name(package, capability, repo_match, opts) do
    with :error <- locked_package(package, capability, repo_match, opts),
         {:ok, records} <- package_project_records(package.system_name, repo_match, opts),
         {:ok, resolution} <-
           select_package_name(records, package.system_name, capability, repo_match) do
      {:ok, apply_resolution(package, resolution)}
    else
      {:ok, package} -> {:ok, package}
      {:error, {:http_error, 404, _body}} -> {:ok, package}
      {:error, :package_project_not_found} -> {:ok, package}
      {:error, {:package_resolution_not_found, _capability, _repo_match}} -> {:ok, package}
      error -> error
    end
  end

  defp package_project_records(package_name, repo_match, opts) do
    case repology_client(opts).project(package_name, repology_opts(opts)) do
      {:ok, records} -> {:ok, records}
      {:error, {:http_error, 404, _body}} -> project_by_package(package_name, repo_match, opts)
      error -> error
    end
  end

  defp project_by_package(package_name, repo_match, opts) do
    repo_match
    |> discovery_repos()
    |> Enum.reduce_while({:error, :package_project_not_found}, fn repo, _error ->
      case repology_client(opts).project_by_package(repo, package_name, repology_opts(opts)) do
        {:ok, records} -> {:halt, {:ok, records}}
        {:error, {:http_error, 404, _body}} -> {:cont, {:error, :package_project_not_found}}
        error -> {:halt, error}
      end
    end)
  end

  defp discovery_repos(repo) when is_binary(repo),
    do: Enum.uniq([repo, "debian_13", "ubuntu_24_04"])

  defp discovery_repos(_repo_match), do: ["debian_13", "ubuntu_24_04"]

  defp repo_match(%PackageResource{meta: %{package_repo: repo}}, _opts) when is_binary(repo),
    do: {:ok, repo}

  defp repo_match(_package, opts) do
    cond do
      is_binary(Keyword.get(opts, :package_repo)) ->
        {:ok, Keyword.fetch!(opts, :package_repo)}

      match?(%Regex{}, Keyword.get(opts, :package_repo)) ->
        {:ok, Keyword.fetch!(opts, :package_repo)}

      Keyword.get(opts, :package_manager) in Map.keys(@manager_repos) ->
        {:ok, Map.fetch!(@manager_repos, Keyword.fetch!(opts, :package_manager))}

      true ->
        TargetRepo.detect(opts)
    end
  end

  defp repology_client(opts),
    do: Keyword.get(opts, :repology_client, HostKit.Package.Repology.CachedClient)

  defp repology_opts(opts) do
    opts
    |> Keyword.take([
      :repology_base_url,
      :repology_site_url,
      :repology_user_agent,
      :repology_timeout,
      :repology_rate_limit,
      :repology_cache,
      :repology_cache_dir,
      :repology_cache_ttl,
      :req_options
    ])
    |> Enum.map(fn
      {:repology_base_url, value} -> {:base_url, value}
      {:repology_site_url, value} -> {:site_url, value}
      {:repology_user_agent, value} -> {:user_agent, value}
      {:repology_timeout, value} -> {:timeout, value}
      {:repology_rate_limit, value} -> {:rate_limit, value}
      {:repology_cache, value} -> {:cache, value}
      {:repology_cache_dir, value} -> {:cache_dir, value}
      {:repology_cache_ttl, value} -> {:cache_ttl, value}
      other -> other
    end)
  end

  defp select_preferred_package(records, capability, preferred_names, repo_match) do
    matches = Enum.filter(records, &repo_match?(&1.repo, repo_match))

    candidates =
      matches |> Enum.flat_map(&record_package_candidates/1) |> Enum.uniq_by(& &1.package)

    case choose_preferred_package(candidates, preferred_names) do
      {:ok, resolution} ->
        {:ok,
         repology_resolution(
           resolution,
           capability,
           inferred_project(records, to_string(capability)),
           records
         )}

      :none ->
        {:error, {:package_resolution_not_found, capability, repo_match}}

      {:ambiguous, candidates} ->
        names = Enum.map(candidates, & &1.package)
        {:error, {:ambiguous_package_resolution, capability, repo_match, names}}
    end
  end

  defp select_development_package(records, capability, project, repo_match) do
    matches = Enum.filter(records, &repo_match?(&1.repo, repo_match))

    candidates =
      matches |> Enum.flat_map(&record_package_candidates/1) |> Enum.uniq_by(& &1.package)

    dev_candidates = Enum.filter(candidates, &development_package?/1)

    choice =
      case dev_candidates do
        [] -> choose_package_name(candidates, matches, project)
        candidates -> choose_development_package(candidates, matches, project)
      end

    case choice do
      {:ok, resolution} ->
        {:ok,
         repology_resolution(resolution, capability, inferred_project(records, project), records)}

      :none ->
        {:error, {:package_resolution_not_found, capability, repo_match}}

      {:ambiguous, candidates} ->
        names = Enum.map(candidates, & &1.package)
        {:error, {:ambiguous_package_resolution, capability, repo_match, names}}
    end
  end

  defp choose_preferred_package([], _preferred_names), do: :none

  defp choose_preferred_package(candidates, preferred_names) do
    find_preferred_candidate(candidates, preferred_names)
  end

  defp choose_development_package(candidates, records, project) do
    preferred_names =
      records
      |> Enum.flat_map(&[&1.srcname, &1.visiblename, project])
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(&development_names/1)
      |> Enum.uniq()

    find_preferred_candidate(candidates, preferred_names)
  end

  defp select_package_name(records, package_name, capability, repo_match) do
    matches = Enum.filter(records, &repo_match?(&1.repo, repo_match))

    candidates =
      matches |> Enum.flat_map(&record_package_candidates/1) |> Enum.uniq_by(& &1.package)

    case choose_package_name(candidates, matches, package_name) do
      {:ok, resolution} ->
        {:ok,
         %{
           resolution
           | capability: capability,
             source: repology_source(records),
             project: inferred_project(records, package_name)
         }}

      :none ->
        {:error, {:package_resolution_not_found, capability, repo_match}}

      {:ambiguous, candidates} ->
        names = Enum.map(candidates, & &1.package)
        {:error, {:ambiguous_package_resolution, capability, repo_match, names}}
    end
  end

  defp choose_package_name([], _records, _package_name), do: :none

  defp choose_package_name([%Resolution{} = resolution], _records, _package_name),
    do: {:ok, resolution}

  defp choose_package_name(candidates, records, package_name) do
    preferred_names =
      [package_name]
      |> Kernel.++(records |> Enum.flat_map(&[&1.srcname, &1.visiblename]))
      |> Kernel.++(Enum.map(candidates, & &1.package))
      |> Enum.reject(&(is_nil(&1) or package_variant?(&1)))
      |> Enum.uniq()

    find_preferred_candidate(candidates, preferred_names)
  end

  defp find_preferred_candidate([%Resolution{} = resolution], _preferred_names),
    do: {:ok, resolution}

  defp find_preferred_candidate(candidates, preferred_names) do
    Enum.find_value(preferred_names, fn name ->
      case Enum.filter(candidates, &(&1.package == name)) do
        [resolution] -> {:ok, resolution}
        [] -> nil
        matches -> {:ambiguous, matches}
      end
    end) || {:ambiguous, candidates}
  end

  defp package_variant?(name) do
    String.contains?(name, ["-dev", "-devel", "-doc", "-docs", "-static"]) or
      String.starts_with?(name, ["python", "mingw", "lib32-"])
  end

  defp development_package?(%Resolution{package: package}) do
    String.ends_with?(package, ["-dev", "-devel"])
  end

  defp development_names(name), do: ["#{name}-dev", "#{name}-devel", name]

  defp dev_capability?(capability) when is_atom(capability) do
    capability |> Atom.to_string() |> String.ends_with?("_dev")
  end

  defp dev_capability?(_capability), do: false

  defp repology_resolution(%Resolution{} = resolution, capability, project, records) do
    %{resolution | capability: capability, source: repology_source(records), project: project}
  end

  defp repology_source(records) do
    records
    |> Enum.map(&get_in(&1.meta, [:source]))
    |> Enum.find(& &1)
    |> case do
      :cache -> :repology_cache
      :stale_cache -> :repology_stale_cache
      :api -> :repology_api
      _other -> :repology_api
    end
  end

  defp inferred_project(records, fallback) do
    records
    |> Enum.map(& &1.srcname)
    |> Enum.find(&is_binary/1)
    |> Kernel.||(fallback)
  end

  defp record_package_candidates(%Record{} = record) do
    record
    |> package_names()
    |> Enum.map(fn name ->
      %Resolution{package: name, repo: record.repo, candidates: package_names(record)}
    end)
  end

  defp package_names(%Record{binnames: names}) when names != [], do: names
  defp package_names(%Record{binname: name}) when is_binary(name), do: [name]
  defp package_names(%Record{srcname: name}) when is_binary(name), do: [name]
  defp package_names(_record), do: []

  defp repo_match?(repo, %Regex{} = regex), do: Regex.match?(regex, repo)
  defp repo_match?(repo, match) when is_binary(match), do: repo == match

  defp locked_package(package, capability, repo_match, opts) do
    case load_lock(opts) do
      {:ok, lock} -> package_from_lock(package, capability, repo_match, lock)
      :error -> :error
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_lock(opts) do
    cond do
      match?(%HostKit.Package.Lock{}, Keyword.get(opts, :package_lock)) ->
        {:ok, Keyword.fetch!(opts, :package_lock)}

      is_binary(Keyword.get(opts, :package_lock)) ->
        case HostKit.Package.Lock.load(Keyword.fetch!(opts, :package_lock)) do
          {:ok, lock} -> {:ok, lock}
          {:error, :enoent} -> :error
          {:error, reason} -> {:error, reason}
        end

      true ->
        :error
    end
  end

  defp package_from_lock(package, capability, repo_match, lock) do
    case HostKit.Package.Lock.get(lock, capability, repo_match) do
      {:ok, system_name} ->
        resolution = %Resolution{
          capability: capability,
          package: system_name,
          source: :lock,
          repo: lock_repo(lock, repo_match)
        }

        {:ok, apply_resolution(package, resolution)}

      :error ->
        :error

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp lock_repo(_lock, repo) when is_binary(repo), do: repo
  defp lock_repo(%HostKit.Package.Lock{target: target}, _repo), do: target

  defp apply_resolution(package, %Resolution{} = resolution) do
    %{
      package
      | system_name: resolution.package,
        meta: Map.put(package.meta, :resolution, resolution)
    }
  end

  defp capability_package(%Capability{name: name, meta: meta}) do
    %PackageResource{name: name, system_name: to_string(name), source: :semantic, meta: meta}
  end

  defp normalize_capability(name), do: HostKit.Naming.capability_name(name)
end
