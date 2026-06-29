defmodule HostKit.Caddy.Directive.ReverseProxy do
  @moduledoc "Inspectable Caddy reverse_proxy defdirective."

  @type t :: %__MODULE__{upstreams: [String.t()]}

  defstruct upstreams: []
end
