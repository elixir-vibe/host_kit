defmodule HostKit.Resources.Package do
  @moduledoc "Desired OS package installed through the target package manager."

  @type manager :: :apt | :dnf | :pacman | :apk | nil

  @type source :: :semantic | :explicit

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          package: String.t(),
          version: String.t() | nil,
          manager: manager(),
          source: source(),
          update: boolean(),
          depends_on: [term()],
          meta: map()
        }

  defstruct name: nil,
            package: nil,
            version: nil,
            manager: nil,
            source: :semantic,
            update: false,
            depends_on: [],
            meta: %{}

  @spec new(atom() | String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      name: name,
      package: Keyword.get(opts, :package, default_package_name(name)),
      version: Keyword.get(opts, :version),
      manager: Keyword.get(opts, :manager),
      source: Keyword.get(opts, :source, default_source(opts)),
      update: Keyword.get(opts, :update, false),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @spec id(t()) :: {:package, atom() | String.t()}
  def id(%__MODULE__{name: name}), do: {:package, name}

  defp default_source(opts) do
    if Keyword.has_key?(opts, :package), do: :explicit, else: :semantic
  end

  defp default_package_name(name) do
    name
    |> to_string()
    |> String.replace("_", "-")
  end
end
