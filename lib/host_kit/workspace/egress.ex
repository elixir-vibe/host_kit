defmodule HostKit.Workspace.Egress do
  @moduledoc "Workspace egress policy metadata."

  defstruct allow: [], deny: nil, user: nil, meta: %{}

  def id(%__MODULE__{user: user}), do: {:workspace_egress, user}

  def new(opts) do
    struct!(__MODULE__, Map.new(opts))
  end
end
