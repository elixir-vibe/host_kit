defmodule HostKit.Change do
  @moduledoc "A planned change for one HostKit resource."

  alias HostKit.Addr.Resource

  @type action :: :create | :update | :delete | :no_op | :read
  @type t :: %__MODULE__{
          action: action(),
          resource_id: Resource.t() | term(),
          before: struct() | nil,
          after: struct() | nil,
          reason: String.t() | atom() | nil
        }

  defstruct action: nil,
            resource_id: nil,
            before: nil,
            after: nil,
            reason: nil
end
