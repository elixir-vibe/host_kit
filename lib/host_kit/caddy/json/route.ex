defmodule HostKit.Caddy.JSON.Route do
  @moduledoc "Caddy HTTP route."

  use JSONCodec

  defstruct match: [], handle: [], terminal: true

  @type t :: %__MODULE__{match: [struct()], handle: [struct()], terminal: boolean()}
end
