defmodule HostKit.Package.Repology.CachedClient do
  @moduledoc "Repology client wrapper with filesystem caching."

  alias HostKit.Package.Repology.{Cache, Client, Record, Records}

  @spec project(String.t() | atom(), keyword()) :: {:ok, [Record.t()]} | {:error, term()}
  def project(project, opts \\ []) when is_binary(project) or is_atom(project) do
    key = [:api, :project, project]

    key
    |> Cache.fetch_with_source(cache_opts(opts), fn ->
      with {:ok, records} <- base_client(opts).project(project, client_opts(opts)) do
        {:ok, JSONCodec.dump(records)}
      end
    end)
    |> decode_records()
  end

  @spec project_by_package(String.t(), String.t(), keyword()) ::
          {:ok, [Record.t()]} | {:error, term()}
  def project_by_package(repo, package, opts \\ []) when is_binary(repo) and is_binary(package) do
    key = [:site, :project_by, repo, package]

    key
    |> Cache.fetch_with_source(cache_opts(opts), fn ->
      with {:ok, records} <-
             base_client(opts).project_by_package(repo, package, client_opts(opts)) do
        {:ok, JSONCodec.dump(records)}
      end
    end)
    |> decode_records()
  end

  @spec projects(String.t() | nil, keyword()) ::
          {:ok, %{String.t() => [Record.t()]}} | {:error, term()}
  def projects(start \\ nil, opts \\ []) do
    key = [:api, :projects, start || "_"]

    key
    |> Cache.fetch_with_source(cache_opts(opts), fn ->
      with {:ok, projects} <- base_client(opts).projects(start, client_opts(opts)) do
        {:ok, JSONCodec.dump(projects)}
      end
    end)
    |> decode_projects()
  end

  @spec package_names(String.t() | atom(), String.t() | Regex.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def package_names(project, repo_match, opts \\ []) do
    with {:ok, records} <- project(project, opts) do
      {:ok, Records.package_names(records, repo_match)}
    end
  end

  defp decode_records({:ok, value, source}) do
    records = JSONCodec.Decoder.decode(value, {:list, Record}, [], [])
    {:ok, Enum.map(records, &annotate_source(&1, source))}
  end

  defp decode_records({:error, reason}), do: {:error, reason}

  defp decode_projects({:ok, value, source}) do
    projects = JSONCodec.Decoder.decode(value, {:map, :string, {:list, Record}}, [], [])

    {:ok,
     Map.new(projects, fn {project, records} ->
       {project, Enum.map(records, &annotate_source(&1, source))}
     end)}
  end

  defp decode_projects({:error, reason}), do: {:error, reason}

  defp annotate_source(%Record{} = record, source) do
    %{record | meta: Map.put(record.meta, :source, source)}
  end

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
