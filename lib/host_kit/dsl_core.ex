defmodule HostKit.DSLCore do
  @moduledoc "Shared building blocks for HostKit DSL scopes."

  alias HostKit.DSLCore.Stack

  @doc "Import DSLCore macros and install compile-time scope metadata."
  defmacro __using__(_opts) do
    quote do
      alias HostKit.DSLCore, as: DSLCore
      import HostKit.DSLCore, only: [scope: 1, scope: 2, scope: 3]

      def attach(child_name, child) when is_atom(child_name) do
        DSLCore.attach(__MODULE__, child_name, child)
      end

      @before_compile HostKit.DSLCore
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __dsl_core_scope__(_name), do: :error
    end
  end

  @doc "Declare a named process-local DSL scope."
  defmacro scope(name, opts \\ [], block \\ []) when is_atom(name) and is_list(opts) do
    {opts, block} = normalize_scope_args(opts, block)
    caller_module = __CALLER__.module
    key = {caller_module, name}
    accepts = block |> Keyword.get(:do) |> extract_accepts()

    scope = %{
      name: name,
      key: key,
      accepts: accepts
    }

    quote do
      def __dsl_core_scope__(unquote(name)), do: {:ok, unquote(Macro.escape(scope))}

      unquote_splicing(scope_functions(name, key, opts))
    end
  end

  defp normalize_scope_args(opts, []) do
    if Keyword.has_key?(opts, :do), do: {[], opts}, else: {opts, []}
  end

  defp normalize_scope_args(opts, block), do: {opts, block}

  defp extract_accepts(nil), do: []

  defp extract_accepts({:__block__, _meta, expressions}) do
    Enum.flat_map(expressions, &extract_accepts/1)
  end

  defp extract_accepts({:accepts, _meta, [thing]}) when is_atom(thing),
    do: [%{name: thing, via: via(thing)}]

  defp extract_accepts({:accepts, _meta, [thing, opts]}) when is_atom(thing) and is_list(opts) do
    [%{name: thing, via: Keyword.get(opts, :via, via(thing))}]
  end

  defp extract_accepts(_other), do: []

  defp via(name), do: :"add_#{name}"

  defp scope_functions(name, key, opts) do
    if Keyword.get(opts, :helpers, true) do
      build_scope_functions(name, key, opts)
    else
      []
    end
  end

  defp build_scope_functions(name, key, opts) do
    value? = Keyword.has_key?(opts, :value)
    value = Keyword.get(opts, :value)

    push_fun = :"push_#{name}"
    pop_fun = :"pop_#{name}"
    current_fun = :"current_#{name}"
    current_bang_fun = :"current_#{name}!"
    update_fun = :"update_#{name}"
    active_fun = :"#{name}_active?"
    start_fun = :"start_#{name}"
    finish_fun = :"finish_#{name}"

    core = __MODULE__
    escaped_key = Macro.escape(key)
    escaped_value = Macro.escape(value)

    base = []

    base =
      maybe_helper(
        base,
        opts,
        :push,
        quote do
          def unquote(push_fun)(state) do
            unquote(core).start(unquote(escaped_key), unquote(name), state)
          end
        end
      )

    base =
      maybe_helper(
        base,
        opts,
        :pop,
        quote do
          def unquote(pop_fun)() do
            unquote(core).finish(unquote(escaped_key), unquote(name))
          end
        end
      )

    base =
      maybe_helper(
        base,
        opts,
        :current,
        quote do
          def unquote(current_fun)() do
            unquote(core).current(unquote(escaped_key))
          end
        end
      )

    base =
      maybe_helper(
        base,
        opts,
        :current!,
        quote do
          def unquote(current_bang_fun)() do
            unquote(core).current!(unquote(escaped_key))
          end
        end
      )

    base =
      maybe_helper(
        base,
        opts,
        :update,
        quote do
          def unquote(update_fun)(fun) do
            unquote(core).update(unquote(escaped_key), fun)
          end
        end
      )

    base =
      maybe_helper(
        base,
        opts,
        :active,
        quote do
          def unquote(active_fun)() do
            unquote(core).active?(unquote(escaped_key))
          end
        end
      )

    base = Enum.reverse(base)

    value_helpers = []

    value_helpers =
      if value? and Keyword.get(opts, :start, true) do
        [
          quote do
            def unquote(start_fun)() do
              unquote(push_fun)(unquote(escaped_value))
            end
          end
          | value_helpers
        ]
      else
        value_helpers
      end

    value_helpers =
      if value? and Keyword.get(opts, :finish, true) do
        [
          quote do
            def unquote(finish_fun)() do
              unquote(pop_fun)()
              :ok
            end
          end
          | value_helpers
        ]
      else
        value_helpers
      end

    attach_fun = :"attach_#{name}"

    attach_helper =
      quote do
        def unquote(attach_fun)(child) do
          attach(unquote(name), child)
        end
      end

    base ++ Enum.reverse(value_helpers) ++ [attach_helper]
  end

  defp maybe_helper(definitions, opts, name, quoted) do
    if Keyword.get(opts, name, true), do: [quoted | definitions], else: definitions
  end

  @doc "Attach a child value to the nearest active accepting scope."
  def attach(owner, child_name, child) when is_atom(owner) and is_atom(child_name) do
    Stack.active_keys(owner)
    |> Enum.find_value(fn key ->
      with {:ok, scope} <- owner.__dsl_core_scope__(elem(key, 1)),
           accept when not is_nil(accept) <- Enum.find(scope.accepts, &(&1.name == child_name)) do
        update(key, fn parent -> apply(parent.__struct__, accept.via, [parent, child]) end)
        :ok
      else
        _ -> nil
      end
    end) || raise ArgumentError, "no active DSL scope accepts #{inspect(child_name)}"
  end

  @doc "Start a named DSL scope."
  defdelegate start(key, name, state, location \\ nil), to: Stack

  @doc "Finish the active DSL scope."
  defdelegate finish(key, expected_name \\ nil), to: Stack

  @doc "Return true when the keyed scope is active."
  defdelegate active?(key), to: Stack

  @doc "Return the active scope state, or nil when inactive."
  defdelegate current(key), to: Stack

  @doc "Return the active scope state."
  defdelegate current!(key), to: Stack

  @doc "Return the active scope struct."
  defdelegate current_scope!(key), to: Stack

  @doc "Update the active scope state."
  defdelegate update(key, fun), to: Stack

  @doc "Reset a scope stack."
  defdelegate reset(key), to: Stack
end
