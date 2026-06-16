defmodule HostKit.RPC.Exposure do
  @moduledoc "RPC surface exposed by a HostKit service."

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          listener: atom() | String.t(),
          meta: map()
        }

  defstruct [:name, listener: :rpc, meta: %{}]

  @spec new(atom() | String.t(), keyword()) :: t()
  def new(name, opts \\ []) when is_atom(name) or is_binary(name) do
    %__MODULE__{
      name: name,
      listener: Keyword.get(opts, :listener, :rpc),
      meta: Keyword.get(opts, :meta, %{})
    }
  end
end
