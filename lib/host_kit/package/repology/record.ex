defmodule HostKit.Package.Repology.Record do
  @moduledoc "Package record returned by the Repology API."

  use JSONCodec, fast_path: :json

  @type status :: String.t()

  @type t :: %__MODULE__{
          repo: String.t(),
          subrepo: String.t() | nil,
          srcname: String.t() | nil,
          binname: String.t() | nil,
          binnames: [String.t()],
          visiblename: String.t() | nil,
          version: String.t(),
          origversion: String.t() | nil,
          status: status() | nil,
          summary: String.t() | nil,
          categories: [String.t()],
          licenses: [String.t()],
          maintainers: [String.t()],
          meta: map()
        }

  defstruct repo: nil,
            subrepo: nil,
            srcname: nil,
            binname: nil,
            binnames: [],
            visiblename: nil,
            version: nil,
            origversion: nil,
            status: nil,
            summary: nil,
            categories: [],
            licenses: [],
            maintainers: [],
            meta: %{}
end
