defmodule HostKit.Resources.EnvFile do
  @moduledoc "Desired dotenv-compatible env file with redacted secret entries."

  @type source :: {:env, String.t()}
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

  def id(%__MODULE__{path: path}), do: {:env_file, path}
end
