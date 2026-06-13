defmodule HostKit.Logs.Config do
  @moduledoc "Declarative log management intent."

  @type t :: %__MODULE__{
          driver: atom() | nil,
          source: term(),
          identifier: String.t() | atom() | nil,
          format: atom() | nil,
          retention: String.t() | nil,
          max_use: String.t() | nil,
          rotate: keyword(),
          ship: boolean() | nil,
          sensitive: boolean(),
          stdout: atom() | nil,
          stderr: atom() | nil,
          resource_id: term(),
          attributes: map(),
          meta: map()
        }

  defstruct driver: nil,
            source: nil,
            identifier: nil,
            format: nil,
            retention: nil,
            max_use: nil,
            rotate: [],
            ship: nil,
            sensitive: false,
            stdout: nil,
            stderr: nil,
            resource_id: nil,
            attributes: %{},
            meta: %{}
end
