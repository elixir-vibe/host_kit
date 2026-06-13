defmodule HostKit.Monitor.Check do
  @moduledoc "Declarative monitoring check metadata."

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          type: atom(),
          target: String.t() | nil,
          expect: keyword(),
          severity: atom(),
          resource_id: term(),
          meta: map()
        }

  defstruct name: nil,
            type: nil,
            target: nil,
            expect: [],
            severity: :warning,
            resource_id: nil,
            meta: %{}
end
