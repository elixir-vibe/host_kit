defmodule HostKit.Monitor.Endpoint do
  @moduledoc "Provider-neutral external endpoint monitoring intent."

  @type t :: %__MODULE__{
          name: atom() | String.t() | nil,
          group: atom() | String.t() | nil,
          url: String.t(),
          interval: String.t() | nil,
          expect: keyword(),
          alerts: [atom() | String.t() | keyword() | map()],
          severity: atom(),
          source: HostKit.Monitor.Check.t()
        }

  defstruct name: nil,
            group: nil,
            url: nil,
            interval: nil,
            expect: [],
            alerts: [],
            severity: :warning,
            source: nil
end
