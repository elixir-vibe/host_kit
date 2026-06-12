defmodule HostKit.Service do
  @moduledoc "A named group of resources that make up an application or host capability."

  @type t :: %__MODULE__{
          name: atom(),
          resources: [struct()],
          meta: map()
        }

  defstruct name: nil,
            resources: [],
            meta: %{}

  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) when is_atom(name) do
    %__MODULE__{
      name: name,
      resources: Keyword.get(opts, :resources, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @spec add_resource(t(), struct()) :: t()
  def add_resource(%__MODULE__{} = service, resource),
    do: %{service | resources: service.resources ++ [resource]}
end
