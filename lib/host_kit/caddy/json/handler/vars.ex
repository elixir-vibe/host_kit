defmodule HostKit.Caddy.JSON.Handler.Vars do
  @moduledoc "Caddy vars handler, used for HTTP roots."

  use JSONCodec

  defstruct handler: "vars", root: nil

  @type t :: %__MODULE__{handler: String.t(), root: String.t() | nil}
end
