defmodule HostKit.Caddy.JSON.Match.Host do
  @moduledoc "Caddy host matcher."

  use JSONCodec

  defstruct host: []

  @type t :: %__MODULE__{host: [String.t()]}
end
