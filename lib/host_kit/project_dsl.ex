defmodule HostKit.ProjectDSL do
  @moduledoc "Helpers for building project-local HostKit DSLs."

  defmacro __using__(_opts) do
    quote do
      import HostKit.ProjectDSL
      Module.register_attribute(__MODULE__, :host_kit_roots, accumulate: true)
      Module.register_attribute(__MODULE__, :host_kit_prefixes, accumulate: true)
      Module.register_attribute(__MODULE__, :host_kit_service_dsl, accumulate: true)
      @before_compile HostKit.ProjectDSL
    end
  end

  defmacro root(name, path) when is_atom(name) do
    quote bind_quoted: [name: name, path: path] do
      @host_kit_roots {name, path}
    end
  end

  defmacro prefix(name, value) when is_atom(name) do
    quote bind_quoted: [name: name, value: value] do
      @host_kit_prefixes {name, value}
    end
  end

  defmacro defservice(name, do: block) when is_atom(name) do
    definitions = parse_definitions(block)

    quote bind_quoted: [name: name, definitions: Macro.escape(definitions)] do
      @host_kit_service_dsl {name, definitions}
    end
  end

  defmacro __before_compile__(env) do
    roots = env.module |> Module.get_attribute(:host_kit_roots) |> Map.new()
    prefixes = env.module |> Module.get_attribute(:host_kit_prefixes) |> Map.new()
    services = Module.get_attribute(env.module, :host_kit_service_dsl) || []

    service_macros = Enum.flat_map(services, &build_service_macros(&1, roots, prefixes))

    quote do
      defmacro __using__(_opts) do
        quote do
          import unquote(__MODULE__)
        end
      end

      unquote_splicing(service_macros)
    end
  end

  defp parse_definitions({:__block__, _meta, expressions}),
    do: Enum.map(expressions, &parse_definition/1)

  defp parse_definitions(expression), do: [parse_definition(expression)]

  defp parse_definition({:let, _meta, [name, [do: expression]]}) when is_atom(name),
    do: {:let, name, expression}

  defp parse_definition({:path, _meta, [name, root_expression, service_expression]})
       when is_atom(name),
       do: {:path, name, root_expression, service_expression}

  defp parse_definition({:macro, _meta, [name, [do: block]]}) when is_atom(name),
    do: {:macro, name, block}

  defp parse_definition(other),
    do: raise(ArgumentError, "unknown ProjectDSL definition: #{Macro.to_string(other)}")

  defp build_service_macros({service_macro, definitions}, roots, prefixes) do
    context = %{roots: roots, prefixes: prefixes, definitions: definitions}

    [build_service_macro(service_macro) | build_definition_macros(definitions, context)]
  end

  defp build_service_macro(name) do
    quote do
      defmacro unquote(name)(service_name, do: block) do
        quote do
          service unquote(service_name) do
            var!(host_kit_project_dsl_service_name) = unquote(service_name)
            unquote(block)
          end
        end
      end
    end
  end

  defp build_definition_macros(definitions, context) do
    definitions
    |> Enum.flat_map(fn
      {:let, name, expression} ->
        [build_let_macro(name, expression, context)]

      {:path, name, root_expression, service_expression} ->
        build_path_macros(name, root_expression, service_expression, context)

      {:macro, name, block} ->
        [build_block_macro(name, block, context)]
    end)
  end

  defp build_let_macro(name, expression, context) do
    expression = expression |> expand_expression(context) |> Macro.escape()

    quote do
      defmacro unquote(name)() do
        unquote(expression)
      end
    end
  end

  defp build_path_macros(name, root_expression, service_expression, context) do
    root = expand_expression(root_expression, context)
    service = expand_expression(service_expression, context)
    path_macro = build_path_macro(name, root, service)

    alias_name = path_alias(name)

    if alias_name == name do
      [path_macro]
    else
      [path_macro, build_path_macro(alias_name, root, service)]
    end
  end

  defp build_path_macro(name, root, service) do
    root = Macro.escape(root)
    service = Macro.escape(service)

    quote do
      defmacro unquote(name)(child \\ nil) do
        root = unquote(root)
        service = unquote(service)

        quote do
          base = Path.join(unquote(root), to_string(unquote(service)))

          case unquote(child) do
            nil -> base
            value -> Path.join(base, value)
          end
        end
      end
    end
  end

  defp build_block_macro(name, block, context) do
    block = block |> expand_expression(context) |> Macro.escape()

    quote do
      defmacro unquote(name)() do
        unquote(block)
      end
    end
  end

  defp path_alias(name) do
    string = Atom.to_string(name)
    suffix_size = byte_size("_dir")
    prefix_size = byte_size(string) - suffix_size

    case string do
      <<prefix::binary-size(^prefix_size), "_dir">> ->
        :erlang.binary_to_atom(prefix <> "_path", :utf8)

      _other ->
        name
    end
  end

  defp expand_expression({:root, _meta, [name]}, %{roots: roots}) when is_atom(name) do
    Map.fetch!(roots, name)
  end

  defp expand_expression({:prefixed, _meta, [name, value]}, %{prefixes: prefixes} = context)
       when is_atom(name) do
    prefix = Map.fetch!(prefixes, name)
    value = expand_expression(value, context)

    quote do
      unquote(prefix) <> to_string(unquote(value))
    end
  end

  defp expand_expression({:service_name, _meta, []}, _context) do
    quote do
      var!(host_kit_project_dsl_service_name)
    end
  end

  defp expand_expression({name, meta, args}, context) when is_list(args) do
    {name, meta, Enum.map(args, &expand_expression(&1, context))}
  end

  defp expand_expression(list, context) when is_list(list),
    do: Enum.map(list, &expand_expression(&1, context))

  defp expand_expression(other, _context), do: other
end
