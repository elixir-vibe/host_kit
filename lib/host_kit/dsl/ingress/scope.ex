defmodule HostKit.DSL.Ingress.Scope do
  @moduledoc false

  use DSL

  options :ingress_opts do
    field(:path, :string)
    field(:state, :string)
    field(:depends_on, {:array, :any}, default: [])
    field(:meta, :map, default: %{})
  end

  options :server_opts do
    field(:meta, :map, default: %{})
  end

  options :tls_opts do
    field(:email, :string)
    field(:meta, :map, default: %{})
  end

  options :route_opts do
    field(:host, :string)
    field(:path, :string)
    field(:meta, :map, default: %{})
  end

  options :proxy_opts do
    field(:to, :any, required: true)
    field(:rewrite, :string)
    field(:meta, :map, default: %{})
  end

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

  def start_ingress(name, opts, source \\ nil) do
    opts = validate_ingress_opts!(opts, location: source)
    meta = opts |> Map.drop([:depends_on, :meta]) |> Map.merge(opts.meta)
    push_ingress(%HostKit.Ingress{name: name, depends_on: opts.depends_on, meta: meta})
  end

  def finish_ingress do
    pop_ingress()
  end

  def start_server(listen, opts, source \\ nil) do
    opts = validate_server_opts!(opts, location: source)

    push_server(%HostKit.Ingress.Server{
      listen: listen,
      meta: opts.meta
    })
  end

  def finish_server do
    server = pop_server()
    attach_server(server)
  end

  def put_tls(mode, opts, source \\ nil) do
    opts = validate_tls_opts!(opts, location: source)

    update_server(
      &%{
        &1
        | tls: %HostKit.Ingress.TLS{
            mode: mode,
            email: opts.email,
            meta: opts.meta
          }
      }
    )
  end

  def start_route(opts, source \\ nil) do
    opts = validate_route_opts!(opts, location: source)

    push_route(%HostKit.Ingress.Route{
      host: opts.host,
      path: opts.path,
      meta: opts.meta
    })
  end

  def finish_route do
    route = pop_route()
    attach_route(route)
  end

  def put_proxy(opts, source \\ nil) do
    opts = validate_proxy_opts!(opts, location: source)

    proxy = %HostKit.Ingress.Proxy{
      to: opts.to,
      rewrite: opts.rewrite,
      meta: opts.meta
    }

    update_route(&%{&1 | proxy: proxy})
  end
end
