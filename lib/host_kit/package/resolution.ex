defmodule HostKit.Package.Resolution do
  @moduledoc "Resolved package capability metadata."

  @type t :: %__MODULE__{
          capability: atom() | String.t(),
          package: String.t(),
          source: atom(),
          project: String.t() | nil,
          repo: String.t() | nil,
          candidates: [String.t()]
        }

  defstruct capability: nil,
            package: nil,
            source: nil,
            project: nil,
            repo: nil,
            candidates: []
end
