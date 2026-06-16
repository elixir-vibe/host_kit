defmodule HostKit.RPC do
  @moduledoc """
  Service-to-service RPC binding metadata.

  HostKit models the deployment wiring: which service exposes broad RPC surfaces
  and which other services are bound to them. Runtime protocols such as SafeRPC
  own exact operations, schemas, and handshakes.
  """

  alias HostKit.RPC.{Binding, Exposure}

  @type t :: %__MODULE__{
          exposes: [Exposure.t()],
          bindings: [Binding.t()]
        }

  defstruct exposes: [], bindings: []

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      exposes: Keyword.get(opts, :exposes, []),
      bindings: Keyword.get(opts, :bindings, [])
    }
  end

  @spec add_exposure(t(), Exposure.t()) :: t()
  def add_exposure(%__MODULE__{} = rpc, %Exposure{} = exposure),
    do: %{rpc | exposes: rpc.exposes ++ [exposure]}

  @spec add_binding(t(), Binding.t()) :: t()
  def add_binding(%__MODULE__{} = rpc, %Binding{} = binding),
    do: %{rpc | bindings: rpc.bindings ++ [binding]}
end
