defmodule HostKit.Providers.Caddy.DSL do
  @moduledoc "DSL macros for Caddy resources."

  defmacro caddy_site(name, host, opts \\ [], do: block) do
    quote do
      HostKit.Providers.Caddy.Scope.start_site(unquote(name), unquote(host), unquote(opts))
      unquote(block)
      HostKit.DSL.Scope.add_resource(HostKit.Providers.Caddy.Scope.finish_site())
    end
  end

  defmacro caddy_site(host, do: block) do
    quote do
      HostKit.Providers.Caddy.Scope.start_site(unquote(host), unquote(host), [])
      unquote(block)
      HostKit.DSL.Scope.add_resource(HostKit.Providers.Caddy.Scope.finish_site())
    end
  end

  defmacro root(path, opts \\ []) do
    quote do
      HostKit.Providers.Caddy.Scope.add_root(unquote(path), unquote(opts))
    end
  end

  defmacro encode(formats) do
    quote do
      HostKit.Providers.Caddy.Scope.add_encode(unquote(formats))
    end
  end

  defmacro file_server(opts \\ []) do
    quote do
      HostKit.Providers.Caddy.Scope.add_file_server(unquote(opts))
    end
  end

  defmacro reverse_proxy(upstream) do
    quote do
      HostKit.Providers.Caddy.Scope.add_reverse_proxy(unquote(upstream))
    end
  end
end
