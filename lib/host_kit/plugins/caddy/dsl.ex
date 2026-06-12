defmodule HostKit.Plugins.Caddy.DSL do
  @moduledoc "DSL macros for Caddy resources."

  defmacro caddy_site(name, host, do: block) do
    quote do
      HostKit.Plugins.Caddy.Scope.start_site(unquote(name), unquote(host))
      unquote(block)
      HostKit.DSL.Scope.add_resource(HostKit.Plugins.Caddy.Scope.finish_site())
    end
  end

  defmacro caddy_site(host, do: block) do
    quote do
      HostKit.Plugins.Caddy.Scope.start_site(unquote(host), unquote(host))
      unquote(block)
      HostKit.DSL.Scope.add_resource(HostKit.Plugins.Caddy.Scope.finish_site())
    end
  end

  defmacro encode(formats) do
    quote do
      HostKit.Plugins.Caddy.Scope.add_encode(unquote(formats))
    end
  end

  defmacro reverse_proxy(upstream) do
    quote do
      HostKit.Plugins.Caddy.Scope.add_reverse_proxy(unquote(upstream))
    end
  end
end
