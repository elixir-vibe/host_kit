defmodule HostKit.Telemetry.Signal do
  @moduledoc "Declarative OpenTelemetry collection intent."

  @type t :: %__MODULE__{
          service_name: String.t() | atom() | nil,
          signals: [atom()],
          logs: term(),
          metrics: term(),
          traces: term(),
          attributes: map(),
          resource_id: term(),
          meta: map()
        }

  defstruct service_name: nil,
            signals: [],
            logs: nil,
            metrics: nil,
            traces: nil,
            attributes: %{},
            resource_id: nil,
            meta: %{}
end
