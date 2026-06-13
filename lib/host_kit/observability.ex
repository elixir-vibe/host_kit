defmodule HostKit.Observability do
  @moduledoc false

  def config(value) when is_boolean(value), do: value

  def config(opts) do
    opts
    |> Map.new(fn
      {:attributes, attrs} -> {:attributes, Map.new(attrs)}
      pair -> pair
    end)
  end

  def merge(base, override, normalize) when is_function(normalize, 1) do
    cond do
      is_map(base) and override == false -> %{enabled: false}
      match?(%{enabled: false}, base) -> %{enabled: false}
      is_map(base) and override == true -> Map.merge(base, normalize.(true))
      is_map(base) -> merge_maps(base, normalize.(override))
    end
  end

  defp merge_maps(base, override) do
    Map.merge(base, override, fn
      :attributes, left, right -> Map.merge(left, right)
      _key, _left, right -> right
    end)
  end
end
