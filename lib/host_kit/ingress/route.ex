defmodule HostKit.Ingress.Route do
  @moduledoc "Inspectable ingress route declaration."

  @type t :: %__MODULE__{
          host: String.t() | nil,
          path: String.t() | nil,
          proxy: HostKit.Ingress.Proxy.t() | nil,
          meta: map()
        }

  defstruct [:host, :path, :proxy, meta: %{}]
end
