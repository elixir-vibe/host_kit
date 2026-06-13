defmodule HostKit.Monitor.Result do
  @moduledoc "Monitoring check execution result."

  @type t :: %__MODULE__{
          check: HostKit.Monitor.Check.t(),
          status: :ok | :error,
          observed: map(),
          reason: term()
        }

  defstruct check: nil,
            status: nil,
            observed: %{},
            reason: nil

  @spec ok(HostKit.Monitor.Check.t(), map()) :: t()
  def ok(check, observed \\ %{}), do: %__MODULE__{check: check, status: :ok, observed: observed}

  @spec error(HostKit.Monitor.Check.t(), term(), map()) :: t()
  def error(check, reason, observed \\ %{}),
    do: %__MODULE__{check: check, status: :error, reason: reason, observed: observed}
end
