defmodule HostKit.Resources.Readiness do
  @moduledoc "Waits until a set of readiness checks pass."

  @type check :: HostKit.Readiness.Systemd.t() | HostKit.Readiness.HTTP.t()

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          checks: [check()],
          timeout: non_neg_integer(),
          interval: non_neg_integer(),
          depends_on: [term()],
          meta: map()
        }

  defstruct name: nil,
            checks: [],
            timeout: 60_000,
            interval: 500,
            depends_on: [],
            meta: %{}

  @spec new(atom() | String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      name: name,
      checks: Keyword.get(opts, :checks, []),
      timeout: Keyword.get(opts, :timeout, 60_000),
      interval: Keyword.get(opts, :interval, 500),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def id(%__MODULE__{name: name}), do: {:readiness, name}
end
