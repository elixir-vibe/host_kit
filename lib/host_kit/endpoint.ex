defmodule HostKit.Endpoint do
  @moduledoc "Reference to a named listener/endpoint exposed by a HostKit service."

  @type t :: %__MODULE__{
          service: atom() | String.t(),
          name: atom() | String.t(),
          meta: map()
        }

  defstruct [:service, :name, meta: %{}]

  @spec new(atom() | String.t(), atom() | String.t(), keyword()) :: t()
  def new(service, name \\ :default, opts \\ []) do
    %__MODULE__{service: service, name: name, meta: Keyword.get(opts, :meta, %{})}
  end
end
