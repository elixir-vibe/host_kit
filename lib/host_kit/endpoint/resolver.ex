defmodule HostKit.Endpoint.Resolver do
  @moduledoc "Resolves endpoint references against service endpoint/listener declarations."

  alias HostKit.Caddy.Directive.ReverseProxy
  alias HostKit.{Diagnostic, Diagnostics, Endpoint, Proxy, Resource, Service}

  @spec resolve([struct()], [Service.t()]) :: {:ok, [struct()]} | {:error, Diagnostics.t()}
  def resolve(resources, services) do
    index = endpoint_index(services)

    {resources, diagnostics} =
      Enum.map_reduce(resources, [], fn resource, diagnostics ->
        case resolve_resource(resource, index) do
          {:ok, resource} -> {resource, diagnostics}
          {:error, diagnostic} -> {resource, [diagnostic | diagnostics]}
        end
      end)

    case Enum.reverse(diagnostics) do
      [] -> {:ok, resources}
      diagnostics -> {:error, Diagnostics.new(diagnostics)}
    end
  end

  defp endpoint_index(services) do
    Map.new(services, fn %Service{name: service_name} = service ->
      {service_name, service_endpoints(service_name, service)}
    end)
  end

  defp service_endpoints(service_name, %Service{meta: meta}) do
    endpoints =
      meta
      |> Map.get(:endpoints, %{})
      |> Map.new(fn {name, endpoint} -> {name, %{endpoint | service: service_name}} end)

    listeners =
      meta
      |> Map.get(:listeners, %{})
      |> Map.new(fn {name, listener} ->
        {name, endpoint_from_listener(service_name, listener)}
      end)

    Map.merge(listeners, endpoints)
  end

  defp endpoint_from_listener(service_name, listener) do
    %Endpoint{
      service: service_name,
      name: listener.name,
      protocol: listener.protocol,
      host: HostKit.Net.Addr.to_string(listener.on),
      port: listener.port,
      meta: listener.meta
    }
  end

  defp resolve_resource(%HostKit.Caddy.Site{} = site, index) do
    with {:ok, directives} <- resolve_directives(site.directives, index, Resource.id(site)) do
      {:ok, %{site | directives: directives}}
    end
  end

  defp resolve_resource(%Proxy{} = proxy, index) do
    with {:ok, services} <- resolve_proxy_services(proxy.services, index, Resource.id(proxy)) do
      {:ok, %{proxy | services: services}}
    end
  end

  defp resolve_resource(%HostKit.Ingress{} = ingress, index) do
    with {:ok, servers} <- resolve_ingress_servers(ingress.servers, index, Resource.id(ingress)) do
      {:ok, %{ingress | servers: servers}}
    end
  end

  defp resolve_resource(%HostKit.Resources.Readiness{} = readiness, index) do
    with {:ok, checks} <-
           resolve_readiness_checks(readiness.checks, index, Resource.id(readiness)) do
      {:ok, %{readiness | checks: checks}}
    end
  end

  defp resolve_resource(resource, _index), do: {:ok, resource}

  defp resolve_directives(directives, index, resource_id) do
    map_while_ok(directives, fn
      %ReverseProxy{upstreams: upstreams} = directive ->
        with {:ok, upstreams} <- resolve_upstreams(upstreams, index, resource_id) do
          {:ok, %{directive | upstreams: upstreams}}
        end

      directive ->
        {:ok, directive}
    end)
  end

  defp resolve_upstreams(upstreams, index, resource_id) do
    map_while_ok(upstreams, fn
      %Endpoint{} = endpoint ->
        with {:ok, endpoint} <- resolve_endpoint(endpoint, index, resource_id) do
          {:ok, Endpoint.upstream(endpoint)}
        end

      upstream ->
        {:ok, upstream}
    end)
  end

  defp resolve_proxy_services(services, index, resource_id) do
    map_while_ok(services, fn service ->
      with {:ok, targets} <- resolve_targets(service.targets, index, resource_id) do
        {:ok, %{service | targets: targets}}
      end
    end)
  end

  defp resolve_targets(targets, index, resource_id) do
    map_while_ok(targets, fn
      %{to: %Endpoint{} = endpoint} = target ->
        with {:ok, endpoint} <- resolve_endpoint(endpoint, index, resource_id) do
          {:ok, %{target | to: endpoint}}
        end

      target ->
        {:ok, target}
    end)
  end

  defp resolve_ingress_servers(servers, index, resource_id) do
    map_while_ok(servers, fn server ->
      with {:ok, routes} <- resolve_ingress_routes(server.routes, index, resource_id) do
        {:ok, %{server | routes: routes}}
      end
    end)
  end

  defp resolve_ingress_routes(routes, index, resource_id) do
    map_while_ok(routes, fn
      %{proxy: %HostKit.Ingress.Proxy{to: %Endpoint{} = endpoint} = proxy} = route ->
        with {:ok, endpoint} <- resolve_endpoint(endpoint, index, resource_id) do
          {:ok, %{route | proxy: %{proxy | to: endpoint}}}
        end

      route ->
        {:ok, route}
    end)
  end

  defp resolve_readiness_checks(checks, index, resource_id) do
    map_while_ok(checks, fn
      %HostKit.Readiness.HTTP{url: %Endpoint{} = endpoint} = http ->
        with {:ok, endpoint} <- resolve_endpoint(endpoint, index, resource_id) do
          {:ok, %{http | url: endpoint}}
        end

      check ->
        {:ok, check}
    end)
  end

  defp resolve_endpoint(%Endpoint{} = endpoint, index, _resource_id) do
    if Endpoint.resolved?(endpoint) do
      {:ok, endpoint}
    else
      fetch_endpoint(endpoint, index)
    end
  end

  defp fetch_endpoint(%Endpoint{service: service, name: name} = endpoint, index) do
    case get_in(index, [service, name]) do
      %Endpoint{} = resolved ->
        {:ok, merge_endpoint(endpoint, resolved)}

      nil ->
        {:error, endpoint_diagnostic(endpoint, index)}
    end
  end

  defp merge_endpoint(ref, resolved) do
    %{
      resolved
      | service: ref.service,
        name: ref.name,
        meta: Map.merge(resolved.meta, ref.meta)
    }
  end

  defp endpoint_diagnostic(%Endpoint{} = endpoint, index) do
    source = Map.get(endpoint.meta, :source)
    suggestion = endpoint_suggestion(endpoint, index)

    %Diagnostic{
      severity: :error,
      code: :endpoint_unresolved,
      message: "unknown endpoint #{endpoint_label(endpoint)}",
      resource_id: {:endpoint, endpoint.service, endpoint.name},
      file: source && source.file,
      line: source && source.line,
      column: source && source.column,
      details: %{service: endpoint.service, endpoint: endpoint.name, suggestion: suggestion},
      hint: endpoint_hint(endpoint, suggestion)
    }
  end

  defp endpoint_hint(endpoint, nil) do
    "declare endpoint #{inspect(endpoint.name)}, port: ... inside service #{inspect(endpoint.service)}"
  end

  defp endpoint_hint(_endpoint, suggestion) do
    "did you mean #{endpoint_label(suggestion)}?"
  end

  defp endpoint_suggestion(%Endpoint{service: service, name: name}, index) do
    cond do
      endpoints = Map.get(index, service) ->
        endpoints
        |> Map.keys()
        |> closest_to(name, 0.0)
        |> case do
          nil -> nil
          endpoint_name -> %Endpoint{service: service, name: endpoint_name}
        end

      service_name = closest_to(Map.keys(index), service, 0.7) ->
        index
        |> Map.fetch!(service_name)
        |> Map.keys()
        |> closest_to(name, 0.0)
        |> case do
          nil -> %Endpoint{service: service_name, name: :default}
          endpoint_name -> %Endpoint{service: service_name, name: endpoint_name}
        end

      true ->
        nil
    end
  end

  defp closest_to([], _needle, _minimum_score), do: nil

  defp closest_to(values, needle, minimum_score) do
    needle = to_string(needle)

    values
    |> Enum.map(fn value -> {String.jaro_distance(to_string(value), needle), value} end)
    |> Enum.max_by(fn {score, _value} -> score end, fn -> {0.0, nil} end)
    |> case do
      {score, value} when score >= minimum_score -> value
      _other -> nil
    end
  end

  defp endpoint_label(%Endpoint{service: service, name: name}) do
    "#{inspect(service)}.#{inspect(name)}"
  end

  defp map_while_ok(values, fun) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> then(fn
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end)
  end
end
