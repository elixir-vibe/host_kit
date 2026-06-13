defmodule HostKit.Source.Ref do
  @moduledoc "Reference to a declared HostKit source for command/run inputs."

  @type t :: %__MODULE__{name: atom() | String.t()}

  defstruct [:name]

  @spec new(atom() | String.t()) :: t()
  def new(name), do: %__MODULE__{name: name}

  @spec normalize_input(term()) :: t() | String.t()
  def normalize_input(%__MODULE__{} = input), do: input
  def normalize_input({:source, name}), do: new(name)
  def normalize_input(input), do: to_string(input)
end
