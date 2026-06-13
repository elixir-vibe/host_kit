defmodule HostKit.Monitor.Check do
  @moduledoc "Declarative monitoring check metadata."

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          type: atom(),
          target: String.t() | nil,
          expect: keyword(),
          task: String.t() | nil,
          port: non_neg_integer() | nil,
          clean: boolean() | nil,
          severity: atom(),
          resource_id: term(),
          meta: map()
        }

  @fields [:name, :type, :target, :expect, :task, :port, :clean, :severity, :resource_id, :meta]

  defstruct name: nil,
            type: nil,
            target: nil,
            expect: [],
            task: nil,
            port: nil,
            clean: nil,
            severity: :warning,
            resource_id: nil,
            meta: %{}

  @spec new(map() | keyword()) :: t()
  def new(attrs) do
    attrs
    |> Map.new()
    |> Map.take(@fields)
    |> then(&struct!(__MODULE__, &1))
  end
end
