defmodule HostKit.Caddy.Site do
  @moduledoc "Inspectable Caddy site resource."

  alias HostKit.Addr.Resource

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          host: String.t(),
          directives: [struct()],
          depends_on: [term()],
          meta: map()
        }

  defstruct name: nil,
            host: nil,
            directives: [],
            depends_on: [],
            meta: %{}

  @spec id(t()) :: Resource.t()
  def id(%__MODULE__{name: name}), do: Resource.new(:caddy_site, name)
end
