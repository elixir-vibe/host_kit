defmodule HostKit.DSLCore.Option do
  @moduledoc "A field declared in a DSLCore option schema."

  @enforce_keys [:name]
  defstruct name: nil,
            type: :string,
            required?: false,
            default: nil

  @type t :: %__MODULE__{
          name: atom(),
          type: term(),
          required?: boolean(),
          default: term()
        }
end
