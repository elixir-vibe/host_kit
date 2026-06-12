defmodule HostKit.Caddy.JSON.Handler.FileServer do
  @moduledoc "Caddy file_server handler."

  use JSONCodec

  defstruct handler: "file_server", browse: nil

  @type t :: %__MODULE__{handler: String.t(), browse: map() | nil}
end
