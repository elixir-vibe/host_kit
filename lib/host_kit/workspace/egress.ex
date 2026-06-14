defmodule HostKit.Workspace.Egress do
  @moduledoc "Workspace egress policy metadata."

  defstruct allow: [], deny: nil, user: nil, meta: %{}

  def id(%__MODULE__{user: user}), do: {:workspace_egress, user}

  def new(opts) do
    opts
    |> Keyword.update(:user, nil, &HostKit.Account.name!/1)
    |> Map.new()
    |> then(&struct!(__MODULE__, &1))
  end
end
