defmodule HostKit.Resources.EnvFile do
  @moduledoc "Desired dotenv-compatible env file with redacted secret entries."

  @type source :: HostKit.Secret.t()
  @type entry :: {:set, String.t(), String.t()} | {:secret, String.t(), source()}
  @type t :: %__MODULE__{
          path: String.t(),
          entries: [entry()],
          owner: String.t() | nil,
          group: String.t() | nil,
          mode: non_neg_integer() | nil,
          depends_on: [term()],
          meta: map()
        }

  defstruct path: nil,
            entries: [],
            owner: nil,
            group: nil,
            mode: nil,
            depends_on: [],
            meta: %{}

  @spec new(String.t(), keyword()) :: t()
  def new(path, opts \\ []) do
    %__MODULE__{
      path: path,
      entries: Keyword.get(opts, :entries, []),
      owner: normalize_account_name(Keyword.get(opts, :owner)),
      group: normalize_account_name(Keyword.get(opts, :group)),
      mode: opts |> Keyword.get(:mode) |> HostKit.Mode.normalize!(),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def id(%__MODULE__{path: path}), do: {:env_file, path}

  defp normalize_account_name(nil), do: nil
  defp normalize_account_name(name), do: HostKit.Account.name!(name)
end
