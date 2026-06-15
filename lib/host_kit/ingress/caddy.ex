defmodule HostKit.Ingress.Caddy do
  @moduledoc "Renders semantic ingress declarations as Caddy site resources."

  alias HostKit.Caddy.Directive.ReverseProxy
  alias HostKit.Caddy.Site
  alias HostKit.{Ingress, Naming}

  @spec to_sites(Ingress.t()) :: [Site.t()]
  def to_sites(%Ingress{} = ingress) do
    ingress.servers
    |> Enum.flat_map(& &1.routes)
    |> Enum.with_index(1)
    |> Enum.map(&route_to_site(ingress, &1))
  end

  defp route_to_site(%Ingress{} = ingress, {%HostKit.Ingress.Route{host: host} = route, index})
       when is_binary(host) do
    %Site{
      name: site_name(ingress.name, host, index),
      host: host,
      directives: route_directives(route),
      depends_on: ingress.depends_on,
      meta: Map.put(ingress.meta, :ingress, ingress.name)
    }
  end

  defp route_to_site(%Ingress{name: name}, {%HostKit.Ingress.Route{} = route, _index}) do
    raise ArgumentError,
          "ingress #{inspect(name)} route must declare a host for Caddy rendering: #{inspect(route)}"
  end

  defp route_directives(%HostKit.Ingress.Route{proxy: %HostKit.Ingress.Proxy{to: to}}) do
    [%ReverseProxy{upstreams: [proxy_upstream(to)]}]
  end

  defp route_directives(%HostKit.Ingress.Route{} = route) do
    raise ArgumentError, "ingress route #{inspect(route.host)} must declare proxy to: ..."
  end

  defp proxy_upstream(%HostKit.Endpoint{} = endpoint) do
    if HostKit.Endpoint.resolved?(endpoint),
      do: HostKit.Endpoint.upstream(endpoint),
      else: endpoint
  end

  defp proxy_upstream(upstream) when is_binary(upstream), do: upstream

  defp site_name(name, host, index), do: Naming.ingress_route(name, host, index)
end
