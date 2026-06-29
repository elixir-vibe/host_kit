defmodule HostKit.Caddy.Directive.FileServer do
  @moduledoc "Inspectable Caddy file_server directive."

  @type t :: %__MODULE__{browse: boolean()}

  defstruct browse: false
end
