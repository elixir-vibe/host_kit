defmodule HostKit.Resources.User do
  @moduledoc "Desired Linux user."

  @type t :: %__MODULE__{
          name: String.t(),
          system: boolean(),
          home: String.t() | nil,
          shell: String.t() | nil,
          groups: [String.t()],
          depends_on: [term()],
          meta: map()
        }

  defstruct name: nil,
            system: false,
            home: nil,
            shell: nil,
            groups: [],
            depends_on: [],
            meta: %{}

  def id(%__MODULE__{name: name}), do: {:user, name}
end
