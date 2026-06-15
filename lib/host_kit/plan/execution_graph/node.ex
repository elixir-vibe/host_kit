defmodule HostKit.Plan.ExecutionGraph.Node do
  @moduledoc "A node in a HostKit plan execution graph."

  @type t :: %__MODULE__{
          id: term(),
          change: HostKit.Change.t(),
          resource_id: term(),
          action: HostKit.Change.action(),
          resource_type: module() | nil
        }

  @enforce_keys [:id, :change, :resource_id, :action]
  defstruct [:id, :change, :resource_id, :action, :resource_type]
end
