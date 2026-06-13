defmodule HostKit.Caddy.JSON.Server do
  @moduledoc "Caddy HTTP server config."

  use JSONCodec

  alias HostKit.Caddy.JSON.Route

  defstruct listen: [], routes: [], logs: nil

  @type t :: %__MODULE__{listen: [String.t()], routes: [Route.t()], logs: map() | nil}
end
