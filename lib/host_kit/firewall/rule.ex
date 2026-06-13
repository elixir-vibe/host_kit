defmodule HostKit.Firewall.Rule do
  @moduledoc "Declarative firewall rule."

  @type t :: %__MODULE__{
          action: :allow | :deny,
          protocol: atom() | nil,
          ports: [non_neg_integer()],
          from: term(),
          target: term(),
          meta: map()
        }

  defstruct action: nil,
            protocol: nil,
            ports: [],
            from: nil,
            target: nil,
            meta: %{}
end
