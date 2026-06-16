defmodule HostKit.RPC.Binding do
  @moduledoc "RPC binding from one HostKit service to another."

  @type t :: %__MODULE__{
          service: atom() | String.t(),
          surfaces: [atom() | String.t()],
          listener: atom() | String.t(),
          meta: map()
        }

  defstruct [:service, surfaces: [], listener: :rpc, meta: %{}]

  @spec new(atom() | String.t(), keyword()) :: t()
  def new(service, opts \\ []) when is_atom(service) or is_binary(service) do
    %__MODULE__{
      service: service,
      surfaces: normalize_surfaces(opts),
      listener: Keyword.get(opts, :listener, :rpc),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  defp normalize_surfaces(opts) do
    opts
    |> Keyword.get(:rpc, Keyword.get(opts, :surfaces, []))
    |> List.wrap()
  end
end
