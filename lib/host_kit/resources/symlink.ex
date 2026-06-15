defmodule HostKit.Resources.Symlink do
  @moduledoc "Desired symbolic link target with optional ownership."

  @type t :: %__MODULE__{
          path: String.t(),
          to: String.t(),
          owner: String.t() | nil,
          group: String.t() | nil,
          depends_on: [term()],
          meta: map()
        }

  defstruct path: nil,
            to: nil,
            owner: nil,
            group: nil,
            depends_on: [],
            meta: %{}

  @spec new(String.t(), keyword()) :: t()
  def new(path, opts \\ []) do
    %__MODULE__{
      path: path,
      to: Keyword.fetch!(opts, :to),
      owner: normalize_account_name(Keyword.get(opts, :owner)),
      group: normalize_account_name(Keyword.get(opts, :group)),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def id(%__MODULE__{path: path}), do: {:symlink, path}

  defp normalize_account_name(nil), do: nil
  defp normalize_account_name(name), do: HostKit.Account.name!(name)
end
