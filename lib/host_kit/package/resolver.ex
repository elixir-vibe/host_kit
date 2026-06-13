defmodule HostKit.Package.Resolver do
  @moduledoc "Resolves semantic package capabilities to concrete OS package names."

  alias HostKit.Package.Repology.Record
  alias HostKit.Package.Resolution
  alias HostKit.Resources.Package, as: PackageResource

  @callback resolve(PackageResource.t(), keyword()) ::
              {:ok, PackageResource.t()} | {:error, term()}

  @capabilities %{
    openssl_dev: %{project: "openssl", package: ~r/(^libssl-dev$|^openssl-dev(el)?$)/},
    ncurses_dev: %{project: "ncurses", package: ~r/(^libncurses-dev$|^ncurses.*-dev(el)?$)/},
    cxx_compiler: %{project: "gcc", package: ~r/^(g\+\+|gcc-c\+\+)$/}
  }

  @manager_repos %{
    apt: ~r/^(debian|ubuntu)_/,
    dnf: ~r/^(fedora|centos|rocky|alma|rhel)_/,
    pacman: ~r/^(arch|archlinux)(_|$)/,
    apk: ~r/^alpine_/
  }

  @spec resolve(PackageResource.t(), keyword()) :: {:ok, PackageResource.t()} | {:error, term()}
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

    case Map.fetch(@capabilities, capability) do
      {:ok, spec} -> resolve_capability(package, capability, spec, opts)
      :error -> {:ok, package}
    end
  end

  defp resolve_capability(package, capability, spec, opts) do
    with {:ok, repo_match} <- repo_match(package, opts),
         {:ok, records} <- repology_client(opts).project(spec.project, repology_opts(opts)),
         {:ok, resolution} <- select_package(records, capability, spec, repo_match) do
      {:ok, apply_resolution(package, resolution)}
    end
  end

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
        {:error, :package_repo_required}
    end
  end

  defp repology_client(opts),
    do: Keyword.get(opts, :repology_client, HostKit.Package.Repology.Client)

  defp repology_opts(opts) do
    opts
    |> Keyword.take([:repology_base_url, :repology_user_agent, :repology_timeout, :req_options])
    |> Enum.map(fn
      {:repology_base_url, value} -> {:base_url, value}
      {:repology_user_agent, value} -> {:user_agent, value}
      {:repology_timeout, value} -> {:timeout, value}
      other -> other
    end)
  end

  defp select_package(records, capability, spec, repo_match) do
    candidates =
      records
      |> Enum.filter(&repo_match?(&1.repo, repo_match))
      |> Enum.flat_map(&record_candidates(&1, spec.package))
      |> Enum.uniq_by(& &1.package)

    case candidates do
      [%Resolution{} = resolution] ->
        {:ok, %{resolution | capability: capability, source: :repology, project: spec.project}}

      [] ->
        {:error, {:package_resolution_not_found, capability, repo_match}}

      candidates ->
        names = Enum.map(candidates, & &1.package)
        {:error, {:ambiguous_package_resolution, capability, repo_match, names}}
    end
  end

  defp record_candidates(%Record{} = record, package_pattern) do
    record
    |> package_names()
    |> Enum.filter(&Regex.match?(package_pattern, &1))
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

  defp apply_resolution(package, %Resolution{} = resolution) do
    %{package | package: resolution.package, meta: Map.put(package.meta, :resolution, resolution)}
  end

  defp normalize_capability(name) when is_atom(name), do: name

  defp normalize_capability(name) when is_binary(name) do
    name |> String.replace("-", "_") |> String.to_existing_atom()
  rescue
    ArgumentError -> name
  end
end
