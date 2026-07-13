defmodule HostKit.Resource do
  @moduledoc "Helpers for resource identity, dependency metadata, and JSON-safe terms."

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
      "fields" => dump_struct_fields(struct)
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
  def dump(value) when is_boolean(value), do: value
  def dump(value) when is_atom(value), do: %{"$type" => "atom", "value" => Atom.to_string(value)}

  def dump(value) when is_binary(value) do
    if String.valid?(value) do
      value
    else
      %{"$type" => "binary", "encoding" => "base64", "value" => Base.encode64(value)}
    end
  end

  def dump(value), do: value

  defp dump_struct_fields(struct) do
    struct
    |> Map.from_struct()
    |> Map.new(fn {key, value} -> {Atom.to_string(key), dump(value)} end)
  end
end
