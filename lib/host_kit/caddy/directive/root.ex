defmodule HostKit.Caddy.Directive.Root do
  @moduledoc "Inspectable Caddy root defdirective."

  @type t :: %__MODULE__{matcher: String.t(), path: String.t()}

  defstruct matcher: "*", path: nil
end
