defmodule HostKit.RPC.Exposure do
  @moduledoc "RPC module exposed by a HostKit service."

  @type t :: %__MODULE__{
          module: module(),
          listener: atom() | String.t(),
          meta: map()
        }

  defstruct [:module, listener: :rpc, meta: %{}]

  @spec new(module(), keyword()) :: t()
  def new(module, opts \\ []) when is_atom(module) do
    %__MODULE__{
      module: module,
      listener: Keyword.get(opts, :listener, :rpc),
      meta: Keyword.get(opts, :meta, %{})
    }
  end
end
