defmodule HostKit.Tenant do
  @moduledoc "Platform tenant metadata."

  @type t :: %__MODULE__{name: atom(), quota: keyword(), meta: map()}
  defstruct name: nil, quota: [], meta: %{}

  def new(name, opts \\ []) when is_atom(name) do
    %__MODULE__{
      name: name,
      quota: Keyword.get(opts, :quota, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end
end
