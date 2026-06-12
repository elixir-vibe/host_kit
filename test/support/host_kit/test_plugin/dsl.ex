defmodule HostKit.TestPlugin.DSL do
  @moduledoc false

  defmacro test_site(host, do: block) do
    quote do
      HostKit.TestPlugin.Scope.start_site(unquote(host))
      unquote(block)
      HostKit.DSL.Scope.add_resource(HostKit.TestPlugin.Scope.finish_site())
    end
  end

  defmacro reverse_proxy(upstream) do
    quote do
      HostKit.TestPlugin.Scope.put_upstream(unquote(upstream))
    end
  end
end
