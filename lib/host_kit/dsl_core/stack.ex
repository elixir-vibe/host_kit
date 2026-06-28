defmodule HostKit.DSLCore.Stack do
  @moduledoc "Process-local stack storage for nested DSL scopes."

  alias HostKit.DSLCore.Scope

  @type key :: term()

  @doc "Push a named scope under a stack key."
  @spec start(key(), atom(), term(), Macro.Env.t() | Scope.location() | nil) :: :ok
  def start(key, name, state, location \\ nil) when is_atom(name) do
    put_stack(key, [Scope.new(name, state, location) | stack(key)])
    :ok
  end

  @doc "Pop the active scope under a stack key and return its state."
  @spec finish(key(), atom() | nil) :: term()
  def finish(key, expected_name \\ nil) do
    case stack(key) do
      [] ->
        raise ArgumentError, "no #{inspect(key)} DSL scope is active"

      [%Scope{name: name} | _rest] when not is_nil(expected_name) and name != expected_name ->
        raise ArgumentError,
              "expected active #{inspect(key)} DSL scope #{inspect(expected_name)}, got #{inspect(name)}"

      [%Scope{state: state} | rest] ->
        put_stack(key, rest)
        state
    end
  end

  @doc "Return true when a scope stack has an active scope."
  @spec active?(key()) :: boolean()
  def active?(key), do: stack(key) != []

  @doc "Return the active scope state or raise."
  @spec current!(key()) :: term()
  def current!(key) do
    case stack(key) do
      [%Scope{state: state} | _rest] -> state
      [] -> raise ArgumentError, "no #{inspect(key)} DSL scope is active"
    end
  end

  @doc "Return the active scope struct or raise."
  @spec current_scope!(key()) :: Scope.t()
  def current_scope!(key) do
    case stack(key) do
      [scope | _rest] -> scope
      [] -> raise ArgumentError, "no #{inspect(key)} DSL scope is active"
    end
  end

  @doc "Update the active scope state."
  @spec update(key(), (term() -> term())) :: :ok
  def update(key, fun) when is_function(fun, 1) do
    case stack(key) do
      [] -> raise ArgumentError, "no #{inspect(key)} DSL scope is active"
      [%Scope{} = scope | rest] -> put_stack(key, [%{scope | state: fun.(scope.state)} | rest])
    end

    :ok
  end

  @doc "Delete all scopes under a key. Intended for test cleanup and loader boundaries."
  @spec reset(key()) :: :ok
  def reset(key) do
    Process.delete(process_key(key))
    :ok
  end

  defp stack(key), do: Process.get(process_key(key), [])
  defp put_stack(key, []), do: Process.delete(process_key(key))
  defp put_stack(key, scopes), do: Process.put(process_key(key), scopes)
  defp process_key(key), do: {__MODULE__, key}
end
