defmodule HostKit.Ingress.Proxy do
  @moduledoc "Inspectable ingress proxy action."

  @type t :: %__MODULE__{
          to: HostKit.Endpoint.t() | String.t(),
          rewrite: String.t() | nil,
          meta: map()
        }

  defstruct [:to, :rewrite, meta: %{}]
end
