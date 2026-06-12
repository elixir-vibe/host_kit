defmodule HostKit.Caddy.JSON.Handler.ReverseProxy do
  @moduledoc "Caddy reverse_proxy handler."

  use JSONCodec

  alias HostKit.Caddy.JSON.Upstream

  defstruct handler: "reverse_proxy", upstreams: []

  @type t :: %__MODULE__{handler: String.t(), upstreams: [Upstream.t()]}
end
