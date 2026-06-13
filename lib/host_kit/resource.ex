defmodule HostKit.Resource do
  @moduledoc "Helpers for resource identity, dependency metadata, and JSON-safe terms."

  @callback id(struct()) :: term()

  @spec id(struct()) :: term()
  def id(resource) do
    Code.ensure_loaded?(resource.__struct__)

    if function_exported?(resource.__struct__, :id, 1) do
      resource.__struct__.id(resource)
    else
      Map.fetch!(resource, :id)
    end
  end

  @spec dump(term()) :: term()
  def dump(%module{} = struct) do
    %{
      "$type" => "struct",
      "module" => Atom.to_string(module),
      "fields" => dump(Map.from_struct(struct))
    }
  end

  def dump(tuple) when is_tuple(tuple) do
    %{"$type" => "tuple", "items" => tuple |> Tuple.to_list() |> dump()}
  end

  def dump(%{} = map) do
    %{
      "$type" => "map",
      "entries" => Enum.map(map, fn {key, value} -> [dump(key), dump(value)] end)
    }
  end

  def dump(values) when is_list(values), do: Enum.map(values, &dump/1)
  def dump(value) when is_atom(value), do: %{"$type" => "atom", "value" => Atom.to_string(value)}
  def dump(value), do: value

  @spec load(term()) :: term()
  def load(%{"$type" => "struct", "module" => module, "fields" => fields}) do
    module = existing_module!(module)
    struct(module, load(fields))
  end

  def load(%{"$type" => "tuple", "items" => items}), do: items |> load() |> List.to_tuple()

  def load(%{"$type" => "map", "entries" => entries}) do
    Map.new(entries, fn [key, value] -> {load(key), load(value)} end)
  end

  def load(%{"$type" => "atom", "value" => value}), do: String.to_existing_atom(value)
  def load(values) when is_list(values), do: Enum.map(values, &load/1)
  def load(value), do: value

  defp existing_module!("Elixir.HostKit" <> _rest = module), do: String.to_existing_atom(module)

  defp existing_module!(module),
    do: raise(ArgumentError, "unsupported HostKit artifact module #{inspect(module)}")
end
