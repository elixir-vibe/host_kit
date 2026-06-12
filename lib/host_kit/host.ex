defmodule HostKit.Host do
  @moduledoc "Host declaration."

  @type t :: %__MODULE__{
          name: atom(),
          hostname: String.t() | nil,
          user: String.t() | nil,
          sudo: boolean(),
          meta: map()
        }

  defstruct name: nil,
            hostname: nil,
            user: nil,
            sudo: true,
            meta: %{}
end
