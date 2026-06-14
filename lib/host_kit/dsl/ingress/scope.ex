defmodule HostKit.DSL.Ingress.Scope do
  @moduledoc false

  @ingress_key {__MODULE__, :ingress}
  @server_key {__MODULE__, :server}
  @route_key {__MODULE__, :route}

  def start_ingress(name, opts) do
    meta = opts |> Keyword.drop([:meta]) |> Map.new() |> Map.merge(Keyword.get(opts, :meta, %{}))
    Process.put(@ingress_key, %HostKit.Ingress{name: name, meta: meta})
  end

  def finish_ingress do
    Process.delete(@ingress_key) || raise "no HostKit ingress in scope"
  end

  def start_server(listen, opts) do
    Process.put(@server_key, %HostKit.Ingress.Server{
      listen: listen,
      meta: Keyword.get(opts, :meta, %{})
    })
  end

  def finish_server do
    server = Process.delete(@server_key) || raise "no HostKit ingress server in scope"
    ingress = Process.get(@ingress_key) || raise "ingress server used outside ingress block"
    Process.put(@ingress_key, %{ingress | servers: ingress.servers ++ [server]})
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
    Process.put(@route_key, %HostKit.Ingress.Route{
      host: Keyword.get(opts, :host),
      path: Keyword.get(opts, :path),
      meta: Keyword.get(opts, :meta, %{})
    })
  end

  def finish_route do
    route = Process.delete(@route_key) || raise "no HostKit ingress route in scope"
    update_server(&%{&1 | routes: &1.routes ++ [route]})
  end

  def put_proxy(opts) do
    proxy = %HostKit.Ingress.Proxy{
      to: Keyword.fetch!(opts, :to),
      rewrite: Keyword.get(opts, :rewrite),
      meta: Keyword.get(opts, :meta, %{})
    }

    update_route(&%{&1 | proxy: proxy})
  end

  defp update_server(fun) do
    server =
      Process.get(@server_key) || raise "ingress server directive used outside server block"

    Process.put(@server_key, fun.(server))
    :ok
  end

  defp update_route(fun) do
    route = Process.get(@route_key) || raise "ingress route directive used outside route block"
    Process.put(@route_key, fun.(route))
    :ok
  end
end
