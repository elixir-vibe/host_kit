defmodule HostKit.Package.Repology.Cache do
  @moduledoc "Filesystem cache for Repology API responses."

  @default_dir ".host_kit/cache/repology"
  @default_ttl :timer.hours(24)

  @spec fetch(term(), keyword(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def fetch(key, opts, fun) do
    case fetch_with_source(key, opts, fun) do
      {:ok, value, _source} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_with_source(term(), keyword(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term(), atom()} | {:error, term()}
  def fetch_with_source(key, opts, fun) do
    if enabled?(opts) do
      fetch_cached(key, opts, fun)
    else
      with {:ok, value} <- fun.(), do: {:ok, value, :api}
    end
  end

  defp fetch_cached(key, opts, fun) do
    path = path(key, opts)

    case read(path, opts) do
      {:ok, value, :fresh} ->
        {:ok, value, :cache}

      {:ok, value, :stale} ->
        refresh(path, fun, {:ok, value})

      :miss ->
        refresh(path, fun, :miss)
    end
  end

  defp refresh(path, fun, fallback) do
    case fun.() do
      {:ok, value} ->
        :ok = write(path, value)
        {:ok, value, :api}

      {:error, _reason} = error ->
        case fallback do
          {:ok, value} -> {:ok, value, :stale_cache}
          :miss -> error
        end
    end
  end

  defp read(path, opts) do
    with {:ok, stat} <- File.stat(path),
         {:ok, content} <- File.read(path),
         {:ok, value} <- Jason.decode(content) do
      state = if fresh?(stat, opts), do: :fresh, else: :stale
      {:ok, value, state}
    else
      {:error, :enoent} -> :miss
      {:error, _reason} -> :miss
    end
  end

  defp write(path, value) do
    with {:ok, content} <- Jason.encode_to_iodata(value, pretty: true),
         :ok <- File.mkdir_p(Path.dirname(path)) do
      HostKit.Runner.Files.write_file(path, content, mode: 0o600)
    end
  end

  defp fresh?(%File.Stat{mtime: mtime}, opts) do
    ttl = Keyword.get(opts, :cache_ttl, @default_ttl)
    modified_at = mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
    DateTime.diff(DateTime.utc_now(), modified_at, :millisecond) <= ttl
  end

  defp path(key, opts) do
    key
    |> List.wrap()
    |> Enum.map(&path_segment/1)
    |> then(&Path.join([Keyword.get(opts, :cache_dir, @default_dir) | &1]))
  end

  defp path_segment(value) do
    value
    |> to_string()
    |> Base.url_encode64(padding: false)
  end

  defp enabled?(opts), do: Keyword.get(opts, :cache, true)
end
