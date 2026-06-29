defmodule HostKit.Ingress.Server do
  @moduledoc "Inspectable ingress server/listener declaration."

  @type t :: %__MODULE__{
          listen: String.t() | pos_integer(),
          tls: HostKit.Ingress.TLS.t() | nil,
          routes: [HostKit.Ingress.Route.t()],
          meta: map()
        }

  defstruct [:listen, :tls, routes: [], meta: %{}]

  def add_route(%__MODULE__{} = server, %HostKit.Ingress.Route{} = route) do
    %{server | routes: server.routes ++ [route]}
  end
end
