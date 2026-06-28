defmodule HostKit.DSLCore do
  @moduledoc "Shared building blocks for HostKit DSL scopes."

  alias HostKit.DSLCore.Stack

  @doc "Start a named DSL scope."
  defdelegate start(key, name, state, location \\ nil), to: Stack

  @doc "Finish the active DSL scope."
  defdelegate finish(key, expected_name \\ nil), to: Stack

  @doc "Return true when the keyed scope is active."
  defdelegate active?(key), to: Stack

  @doc "Return the active scope state."
  defdelegate current!(key), to: Stack

  @doc "Return the active scope struct."
  defdelegate current_scope!(key), to: Stack

  @doc "Update the active scope state."
  defdelegate update(key, fun), to: Stack

  @doc "Reset a scope stack."
  defdelegate reset(key), to: Stack
end
