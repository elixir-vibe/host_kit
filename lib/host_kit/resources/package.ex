defmodule HostKit.Resources.Package do
  @moduledoc "Desired OS package installed through the target package manager."

  @type source :: :semantic | :explicit

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          system_name: String.t(),
          version: String.t() | nil,
          source: source(),
          update: boolean(),
          depends_on: [term()],
          meta: map()
        }

  defstruct name: nil,
            system_name: nil,
            version: nil,
            source: :semantic,
            update: false,
            depends_on: [],
            meta: %{}

  @spec new(atom() | String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      name: name,
      system_name: Keyword.get(opts, :as, default_package_name(name)),
      version: Keyword.get(opts, :version),
      source: Keyword.get(opts, :source, default_source(opts)),
      update: Keyword.get(opts, :update, false),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @spec id(t()) :: {:package, atom() | String.t()}
  def id(%__MODULE__{name: name}), do: {:package, name}

  defp default_source(opts) do
    if Keyword.has_key?(opts, :as), do: :explicit, else: :semantic
  end

  defp default_package_name(name) do
    name
    |> to_string()
    |> String.replace("_", "-")
  end
end
