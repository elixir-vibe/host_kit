defmodule HostKit.Caddy.JSON.Handler.Subroute do
  @moduledoc "Caddy subroute handler."

  use JSONCodec

  alias HostKit.Caddy.JSON.Route

  defstruct handler: "subroute", routes: []

  @type t :: %__MODULE__{handler: String.t(), routes: [Route.t()]}
end
