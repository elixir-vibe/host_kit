defmodule HostKit.Recipe do
  @moduledoc "Reusable HostKit DSL recipes."

  defmacro __using__(_opts) do
    quote do
      import HostKit.Recipe
    end
  end

  defmacro defrecipe(call, do: body) do
    {name, args} = Macro.decompose_call(call)
    recipe_module = __CALLER__.module
    escaped_body = Macro.escape(body)

    quote do
      defmacro unquote(name)(unquote_splicing(args)) do
        bindings = binding()

        body =
          unquote(escaped_body)
          |> Macro.prewalk(fn
            {:__MODULE__, _meta, _context} ->
              unquote(recipe_module)

            {var, meta, context} = node when is_atom(var) and is_atom(context) ->
              if Keyword.has_key?(bindings, var) do
                Keyword.fetch!(bindings, var)
              else
                node
              end

            node ->
              node
          end)

        quote do
          unquote(body)
        end
      end
    end
  end
end
