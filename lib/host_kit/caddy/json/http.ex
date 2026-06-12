defmodule HostKit.Caddy.JSON.HTTP do
  @moduledoc "Caddy HTTP app config."

  use JSONCodec

  alias HostKit.Caddy.JSON.Server

  defstruct servers: %{}

  @type t :: %__MODULE__{servers: %{String.t() => Server.t()}}
end
