defmodule HostKit.Addr.Resource do
  @moduledoc "Stable address for a resource declaration."

  @type mode :: :managed | :data | :ephemeral
  @type t :: %__MODULE__{mode: mode(), type: atom(), name: atom() | String.t()}

  defstruct mode: :managed, type: nil, name: nil

  @spec new(atom(), atom() | String.t(), keyword()) :: t()
  def new(type, name, opts \\ []) when is_atom(type) do
    %__MODULE__{mode: Keyword.get(opts, :mode, :managed), type: type, name: name}
  end

  defimpl String.Chars do
    def to_string(%{mode: :managed, type: type, name: name}), do: "#{type}.#{name}"
    def to_string(%{mode: mode, type: type, name: name}), do: "#{mode}.#{type}.#{name}"
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(resource, _opts) do
      concat(["#HostKit.Resource<", to_string(resource), ">"])
    end
  end
end
