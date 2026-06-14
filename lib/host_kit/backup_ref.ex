defmodule HostKit.BackupRef do
  @moduledoc "Reference to a backup payload captured in a tracked HostKit run."

  @type t :: %__MODULE__{path: String.t()}
  defstruct path: nil
end
