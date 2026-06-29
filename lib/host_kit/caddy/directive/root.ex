defmodule HostKit.Caddy.Directive.Root do
  @moduledoc "Inspectable Caddy root directive."

  @type t :: %__MODULE__{matcher: String.t(), path: String.t()}

  defstruct matcher: "*", path: nil
end
