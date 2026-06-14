defmodule HostKit.Ingress do
  @moduledoc "Inspectable ingress/application-router declaration."

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          servers: [HostKit.Ingress.Server.t()],
          depends_on: [term()],
          meta: map()
        }

  defstruct [:name, servers: [], depends_on: [], meta: %{}]

  def id(%__MODULE__{name: name}), do: {:ingress, name}
end
