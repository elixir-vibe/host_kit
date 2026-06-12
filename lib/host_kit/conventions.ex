defmodule HostKit.Conventions do
  @moduledoc "Project-level naming and path conventions."

  @type t :: %__MODULE__{
          roots: %{optional(atom()) => String.t()},
          prefixes: %{optional(atom()) => String.t()}
        }

  defstruct roots: %{}, prefixes: %{}

  @spec new(keyword() | map()) :: t()
  def new(attrs \\ []) do
    %__MODULE__{
      roots: attrs |> get(:roots, %{}) |> Map.new(),
      prefixes: attrs |> get(:prefixes, %{}) |> Map.new()
    }
  end

  @spec put_root(t(), atom(), String.t()) :: t()
  def put_root(%__MODULE__{} = conventions, name, path) when is_atom(name) do
    %{conventions | roots: Map.put(conventions.roots, name, path)}
  end

  @spec put_prefix(t(), atom(), String.t()) :: t()
  def put_prefix(%__MODULE__{} = conventions, name, prefix) when is_atom(name) do
    %{conventions | prefixes: Map.put(conventions.prefixes, name, prefix)}
  end

  @spec root!(t() | map(), atom()) :: String.t()
  def root!(conventions, name) do
    conventions
    |> normalize()
    |> Map.fetch!(:roots)
    |> Map.fetch!(name)
  end

  @spec prefixed(t() | map(), atom(), term()) :: String.t()
  def prefixed(conventions, name, value) do
    prefix = conventions |> normalize() |> Map.fetch!(:prefixes) |> Map.get(name, "")
    prefix <> to_string(value)
  end

  defp normalize(%__MODULE__{} = conventions), do: Map.from_struct(conventions)
  defp normalize(conventions) when is_map(conventions), do: conventions

  defp get(attrs, key, default) when is_list(attrs), do: Keyword.get(attrs, key, default)
  defp get(attrs, key, default) when is_map(attrs), do: Map.get(attrs, key, default)
end
