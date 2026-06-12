defmodule HostKit.Resources.File do
  @moduledoc "Desired file content with ownership and mode."

  @type t :: %__MODULE__{
          path: String.t(),
          content: iodata() | nil,
          owner: String.t() | nil,
          group: String.t() | nil,
          mode: non_neg_integer() | nil,
          depends_on: [term()],
          meta: map()
        }

  defstruct path: nil,
            content: nil,
            owner: nil,
            group: nil,
            mode: nil,
            depends_on: [],
            meta: %{}

  def id(%__MODULE__{path: path}), do: {:file, path}
end
