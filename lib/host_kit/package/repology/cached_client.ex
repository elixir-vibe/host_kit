defmodule HostKit.Package.Repology.CachedClient do
  @moduledoc "Repology client wrapper with filesystem caching."

  alias HostKit.Package.Repology.{Cache, Client, Record, Records}

  @spec project(String.t() | atom(), keyword()) :: {:ok, [Record.t()]} | {:error, term()}
  def project(project, opts \\ []) when is_binary(project) or is_atom(project) do
    key = [:api, :project, project]

    Cache.fetch(key, cache_opts(opts), fn ->
      with {:ok, records} <- base_client(opts).project(project, client_opts(opts)) do
        {:ok, JSONCodec.dump(records)}
      end
    end)
    |> decode({:list, Record})
  end

  @spec project_by_package(String.t(), String.t(), keyword()) ::
          {:ok, [Record.t()]} | {:error, term()}
  def project_by_package(repo, package, opts \\ []) when is_binary(repo) and is_binary(package) do
    key = [:site, :project_by, repo, package]

    Cache.fetch(key, cache_opts(opts), fn ->
      with {:ok, records} <-
             base_client(opts).project_by_package(repo, package, client_opts(opts)) do
        {:ok, JSONCodec.dump(records)}
      end
    end)
    |> decode({:list, Record})
  end

  @spec projects(String.t() | nil, keyword()) ::
          {:ok, %{String.t() => [Record.t()]}} | {:error, term()}
  def projects(start \\ nil, opts \\ []) do
    key = [:api, :projects, start || "_"]

    Cache.fetch(key, cache_opts(opts), fn ->
      with {:ok, projects} <- base_client(opts).projects(start, client_opts(opts)) do
        {:ok, JSONCodec.dump(projects)}
      end
    end)
    |> decode({:map, :string, {:list, Record}})
  end

  @spec package_names(String.t() | atom(), String.t() | Regex.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def package_names(project, repo_match, opts \\ []) do
    with {:ok, records} <- project(project, opts) do
      {:ok, Records.package_names(records, repo_match)}
    end
  end

  defp decode({:ok, value}, type), do: {:ok, JSONCodec.Decoder.decode(value, type, [], [])}
  defp decode({:error, reason}, _type), do: {:error, reason}

  defp cache_opts(opts) do
    opts
    |> Keyword.take([:cache, :cache_dir, :cache_ttl])
    |> Enum.map(fn
      {:cache_dir, value} -> {:cache_dir, value}
      {:cache_ttl, value} -> {:cache_ttl, value}
      other -> other
    end)
  end

  defp client_opts(opts) do
    Keyword.drop(opts, [:cache, :cache_dir, :cache_ttl, :base_client])
  end

  defp base_client(opts), do: Keyword.get(opts, :base_client, Client)
end
