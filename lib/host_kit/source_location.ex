defmodule HostKit.SourceLocation do
  @moduledoc "Source location metadata for HostKit DSL resources."

  @type t :: %{file: String.t() | nil, line: pos_integer() | nil, column: pos_integer() | nil}

  def from_caller(%Macro.Env{} = caller) do
    %{file: caller.file, line: caller.line, column: nil}
  end
end
