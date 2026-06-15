defmodule HostKit.Ingress.Gatehouse do
  @moduledoc "Renders semantic ingress declarations as Gatehouse proxy config resources."

  alias HostKit.{Endpoint, Ingress, Naming, Proxy}

  @spec to_proxy(Ingress.t()) :: Proxy.t()
  def to_proxy(%Ingress{} = ingress) do
    %Proxy{
      name: ingress.name,
      provider: :gatehouse,
      path: Map.get(ingress.meta, :path, "/etc/gatehouse/config.exs"),
      state: Map.get(ingress.meta, :state),
      listeners: ingress.servers |> Enum.map(&listener/1) |> Enum.uniq(),
      services:
        ingress.servers
        |> Enum.flat_map(& &1.routes)
        |> Enum.with_index(1)
        |> Enum.map(&service(ingress, &1)),
      meta: Map.put(ingress.meta, :ingress, ingress.name)
    }
  end

  defp listener(%HostKit.Ingress.Server{listen: listen, tls: tls}) do
    %{scheme: listener_scheme(tls), opts: [port: listen_port(listen)]}
  end

  defp listener_scheme(%HostKit.Ingress.TLS{mode: mode}) when mode in [:auto, :manual], do: :https
  defp listener_scheme(_tls), do: :http

  defp listen_port(port) when is_integer(port), do: port

  defp listen_port(listen) when is_binary(listen) do
    listen
    |> String.split(":", trim: true)
    |> List.last()
    |> case do
      nil ->
        raise ArgumentError, "Gatehouse ingress listener must include a port: #{inspect(listen)}"

      port ->
        String.to_integer(port)
    end
  end

  defp service(%Ingress{} = ingress, {%HostKit.Ingress.Route{host: host} = route, index})
       when is_binary(host) do
    %{
      name: service_name(ingress.name, host, index),
      hosts: [host],
      targets: [target(route)],
      balance: nil,
      health: nil,
      drain: nil,
      tls: nil,
      meta: Map.put(route.meta, :ingress, ingress.name)
    }
  end

  defp service(%Ingress{name: name}, {%HostKit.Ingress.Route{} = route, _index}) do
    raise ArgumentError,
          "ingress #{inspect(name)} route must declare a host for Gatehouse rendering: #{inspect(route)}"
  end

  defp target(%HostKit.Ingress.Route{proxy: %HostKit.Ingress.Proxy{to: to}}) do
    %{name: :main, url: target_url(to), active: true, metadata: %{}}
  end

  defp target(%HostKit.Ingress.Route{} = route) do
    raise ArgumentError, "ingress route #{inspect(route.host)} must declare proxy to: ..."
  end

  defp target_url(%Endpoint{} = endpoint) do
    if Endpoint.resolved?(endpoint), do: Endpoint.url(endpoint), else: endpoint
  end

  defp target_url(url) when is_binary(url), do: url

  defp service_name(name, host, index), do: Naming.ingress_route_name(name, host, index)
end
