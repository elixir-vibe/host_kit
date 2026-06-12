defmodule HostKit.Caddy.JSON.Apps do
  @moduledoc "Caddy JSON apps object."

  use JSONCodec

  alias HostKit.Caddy.JSON.HTTP

  defstruct http: %HTTP{}

  @type t :: %__MODULE__{http: HTTP.t()}
end
