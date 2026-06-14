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

  @spec new(String.t(), keyword()) :: t()
  def new(path, opts \\ []) do
    %__MODULE__{
      path: path,
      content: Keyword.get(opts, :content),
      owner: normalize_account_name(Keyword.get(opts, :owner)),
      group: normalize_account_name(Keyword.get(opts, :group)),
      mode: opts |> Keyword.get(:mode) |> HostKit.Mode.normalize!(),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def id(%__MODULE__{path: path}), do: {:file, path}

  defp normalize_account_name(nil), do: nil
  defp normalize_account_name(name), do: HostKit.Account.name!(name)
end
