defmodule HostKit.Resources.Account do
  @moduledoc "Desired Linux account."

  @type t :: %__MODULE__{
          name: String.t(),
          system: boolean(),
          home: String.t() | nil,
          shell: String.t() | nil,
          groups: [String.t()],
          rollback: :keep,
          depends_on: [term()],
          meta: map()
        }

  defstruct name: nil,
            system: false,
            home: nil,
            shell: nil,
            groups: [],
            rollback: :keep,
            depends_on: [],
            meta: %{}

  def id(%__MODULE__{name: name}), do: {:account, name}
end
