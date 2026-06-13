defmodule HostKit.Diagnostic do
  @moduledoc "Structured HostKit diagnostic, suitable for pattern matching and compiler-style rendering."

  @type severity :: :error | :warning | :info

  @type t :: %__MODULE__{
          severity: severity(),
          code: atom(),
          message: String.t(),
          resource_id: term(),
          file: String.t() | nil,
          line: pos_integer() | nil,
          column: pos_integer() | nil,
          details: map(),
          hint: String.t() | nil
        }

  defstruct severity: :error,
            code: nil,
            message: nil,
            resource_id: nil,
            file: nil,
            line: nil,
            column: nil,
            details: %{},
            hint: nil
end
