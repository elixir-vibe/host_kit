defmodule HostKit.Providers.Caddy.DSL do
  @moduledoc "DSL macros for Caddy resources."

  use DSL.Macros

  alias HostKit.DSL.Scope, as: HostScope
  alias HostKit.Providers.Caddy.Scope

  defblock caddy_site(name, host, opts \\ []) do
    start(Scope.start_site(name, host, opts))
    finish(HostScope.add_resource(Scope.finish_site()))
  end

  defmacro caddy_site(host, do: block) do
    quote do
      caddy_site unquote(host), unquote(host) do
        unquote(block)
      end
    end
  end

  defdirective root(path, opts \\ []) do
    Scope.add_root(path, opts)
  end

  defdirective encode(formats) do
    Scope.add_encode(formats)
  end

  defdirective file_server(opts \\ []) do
    Scope.add_file_server(opts)
  end

  defdirective reverse_proxy(upstream) do
    Scope.add_reverse_proxy(upstream)
  end
end
