defmodule HostKit.Caddy.JSON.Handler.Encode do
  @moduledoc "Caddy encode handler."

  use JSONCodec

  defstruct handler: "encode", encodings: %{}

  @type t :: %__MODULE__{handler: String.t(), encodings: map()}
end
