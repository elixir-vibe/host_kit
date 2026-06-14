defmodule HostKit.Ingress.TLS do
  @moduledoc "Inspectable ingress TLS termination declaration."

  @type t :: %__MODULE__{mode: :auto | :off | :manual, email: String.t() | nil, meta: map()}

  defstruct mode: :auto, email: nil, meta: %{}
end
