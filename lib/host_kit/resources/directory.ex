defmodule HostKit.Resources.Directory do
  @moduledoc "Desired directory with ownership and mode."

  @type t :: %__MODULE__{
          path: String.t(),
          owner: String.t() | nil,
          group: String.t() | nil,
          mode: non_neg_integer() | nil,
          depends_on: [term()],
          meta: map()
        }

  defstruct path: nil,
            owner: nil,
            group: nil,
            mode: nil,
            depends_on: [],
            meta: %{}

  def id(%__MODULE__{path: path}), do: {:directory, path}
end
