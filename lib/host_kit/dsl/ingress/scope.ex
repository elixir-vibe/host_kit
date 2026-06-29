defmodule HostKit.DSL.Ingress.Scope do
  @moduledoc false

  use HostKit.DSLCore

  scope :ingress do
    accepts(:server)
  end

  scope :server do
    requires(:ingress)
    accepts(:route)
  end

  scope :route do
    requires(:server)
  end

  def start_ingress(name, opts) do
    meta = opts |> Keyword.drop([:meta]) |> Map.new() |> Map.merge(Keyword.get(opts, :meta, %{}))
    push_ingress(%HostKit.Ingress{name: name, meta: meta})
  end

  def finish_ingress do
    pop_ingress()
  end

  def start_server(listen, opts) do
    push_server(%HostKit.Ingress.Server{
      listen: listen,
      meta: Keyword.get(opts, :meta, %{})
    })
  end

  def finish_server do
    server = pop_server()
    attach_server(server)
  end

  def put_tls(mode, opts) do
    update_server(
      &%{
        &1
        | tls: %HostKit.Ingress.TLS{
            mode: mode,
            email: Keyword.get(opts, :email),
            meta: Keyword.get(opts, :meta, %{})
          }
      }
    )
  end

  def start_route(opts) do
    push_route(%HostKit.Ingress.Route{
      host: Keyword.get(opts, :host),
      path: Keyword.get(opts, :path),
      meta: Keyword.get(opts, :meta, %{})
    })
  end

  def finish_route do
    route = pop_route()
    attach_route(route)
  end

  def put_proxy(opts) do
    proxy = %HostKit.Ingress.Proxy{
      to: Keyword.fetch!(opts, :to),
      rewrite: Keyword.get(opts, :rewrite),
      meta: Keyword.get(opts, :meta, %{})
    }

    update_route(&%{&1 | proxy: proxy})
  end
end
