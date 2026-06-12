defmodule HostKit.Caddy.JSON.Upstream do
  @moduledoc "Caddy upstream dial target."

  use JSONCodec

  defstruct dial: nil

  @type t :: %__MODULE__{dial: String.t()}
end
