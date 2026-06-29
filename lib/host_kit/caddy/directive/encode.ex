defmodule HostKit.Caddy.Directive.Encode do
  @moduledoc "Inspectable Caddy encode defdirective."

  @type t :: %__MODULE__{formats: [atom() | String.t()]}

  defstruct formats: []
end
