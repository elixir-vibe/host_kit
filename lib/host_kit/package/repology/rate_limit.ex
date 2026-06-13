defmodule HostKit.Package.Repology.RateLimit do
  @moduledoc "Repology API rate limiter backed by Hammer."

  use Hammer, backend: :atomic, algorithm: :leaky_bucket

  @key "repology_api"
  @leak_rate 1
  @capacity 1
  @cost 1

  @spec wait(keyword()) :: :ok
  def wait(opts \\ []) do
    if Keyword.get(opts, :rate_limit, true) do
      await_slot()
    else
      :ok
    end
  end

  defp await_slot do
    case hit(@key, @leak_rate, @capacity, @cost) do
      {:allow, _level} ->
        :ok

      {:deny, retry_after} ->
        Process.sleep(retry_after)
        await_slot()
    end
  end
end
