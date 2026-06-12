defmodule HostKit.ProviderConfig do
  @moduledoc "Configuration for a HostKit provider instance."

  @type t :: %__MODULE__{
          name: atom(),
          module: module(),
          config: map(),
          meta: map()
        }

  defstruct name: nil,
            module: nil,
            config: %{},
            meta: %{}
end
