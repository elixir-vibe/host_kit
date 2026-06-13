defmodule HostKit.Readiness.Systemd do
  @moduledoc "Systemd readiness check."

  @type t :: %__MODULE__{
          unit: String.t(),
          state: :active,
          restart: boolean()
        }

  defstruct [:unit, state: :active, restart: false]

  @spec new(String.t(), keyword()) :: t()
  def new(unit, opts \\ []) do
    %__MODULE__{
      unit: unit,
      state: Keyword.get(opts, :state, :active),
      restart: Keyword.get(opts, :restart, false)
    }
  end
end
