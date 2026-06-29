defmodule HostKit.Backup.Retention do
  @moduledoc "Retention pruning for HostKit backup output files."

  @patterns ["*.tar.gz", "*.tar.gz.sha256", "backup-*.manifest.json"]

  @spec prune!(Path.t(), keyword(), keyword()) :: [Path.t()]
  def prune!(destination, keep, opts \\ [])
  def prune!(_destination, [], _opts), do: []

  def prune!(destination, keep, opts) do
    case Keyword.get(keep, :days) do
      nil ->
        []

      days when is_integer(days) and days > 0 ->
        prune_older_than!(destination, days, opts)

      days ->
        raise ArgumentError, "backup keep days must be a positive integer, got: #{inspect(days)}"
    end
  end

  defp prune_older_than!(destination, days, opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    cutoff = DateTime.add(now, -days, :day)

    destination
    |> candidate_paths()
    |> Enum.filter(&older_than?(&1, cutoff))
    |> Enum.map(fn path ->
      File.rm!(path)
      path
    end)
  end

  defp candidate_paths(destination) do
    @patterns
    |> Enum.flat_map(&Path.wildcard(Path.join(destination, &1)))
    |> Enum.uniq()
  end

  defp older_than?(path, cutoff) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> DateTime.compare(DateTime.from_unix!(mtime), cutoff) == :lt
      {:error, _reason} -> false
    end
  end
end
