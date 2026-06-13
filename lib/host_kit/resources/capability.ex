defmodule HostKit.Resources.Capability do
  @moduledoc "Desired host capability resolved to installable resources for a target system."

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          candidates: [String.t()],
          depends_on: [term()],
          meta: map()
        }

  defstruct name: nil,
            candidates: [],
            depends_on: [],
            meta: %{}

  @spec new(atom() | String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      name: name,
      candidates: Keyword.fetch!(opts, :candidates),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @spec id(t()) :: {:capability, atom() | String.t()}
  def id(%__MODULE__{name: name}), do: {:capability, name}
end
