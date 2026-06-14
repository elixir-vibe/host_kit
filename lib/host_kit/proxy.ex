defmodule HostKit.Proxy do
  @moduledoc "Generic proxy desired-state resource."

  @type t :: %__MODULE__{
          name: atom(),
          provider: atom(),
          path: String.t(),
          services: [map()],
          meta: map()
        }

  defstruct [:name, :provider, path: "/etc/gatehouse/config.exs", services: [], meta: %{}]

  def id(%__MODULE__{name: name}), do: {:proxy, name}

  def service(name, opts \\ []) do
    %{name: name, hosts: [], targets: [], meta: Keyword.get(opts, :meta, %{})}
  end

  def render(%__MODULE__{} = proxy) do
    proxy
    |> to_quoted()
    |> Code.quoted_to_algebra()
    |> Inspect.Algebra.format(:infinity)
    |> IO.iodata_to_binary()
  end

  def to_quoted(%__MODULE__{provider: :gatehouse} = proxy) do
    block([import_gatehouse_config() | Enum.map(proxy.services, &gatehouse_service_quoted/1)])
  end

  def to_quoted(%__MODULE__{provider: provider}) do
    raise ArgumentError, "unsupported proxy provider #{inspect(provider)}"
  end

  defp import_gatehouse_config do
    {:import, [], [{:__aliases__, [], [:Gatehouse, :Config]}]}
  end

  defp gatehouse_service_quoted(service) do
    expressions =
      Enum.map(service.hosts, &host_quoted/1) ++ Enum.map(service.targets, &target_quoted/1)

    {:service, [], [service.name, [do: block(expressions)]]}
  end

  defp host_quoted(host), do: {:host, [], [host]}

  defp target_quoted(%{name: name, safe_rpc: safe_rpc} = target) when is_list(safe_rpc) do
    {:target, [], [name, target_opts(target, safe_rpc: safe_rpc)]}
  end

  defp target_quoted(%{name: name, to: %HostKit.Endpoint{} = endpoint} = target) do
    if HostKit.Endpoint.resolved?(endpoint) do
      {:target, [], [name, HostKit.Endpoint.url(endpoint), target_opts(target)]}
    else
      {:target, [], [name, endpoint_quoted(endpoint), target_opts(target)]}
    end
  end

  defp target_quoted(%{name: name, url: url} = target) do
    {:target, [], [name, url, target_opts(target)]}
  end

  defp endpoint_quoted(%HostKit.Endpoint{service: service, name: :default}) do
    {:endpoint, [], [service]}
  end

  defp endpoint_quoted(%HostKit.Endpoint{service: service, name: name}) do
    {:endpoint, [], [service, name]}
  end

  defp target_opts(target, opts \\ []) do
    opts
    |> Keyword.merge(
      active: Map.get(target, :active, false),
      metadata: Map.get(target, :metadata, %{})
    )
    |> Enum.reject(fn
      {:active, false} -> true
      {:metadata, metadata} -> metadata == %{}
      {_key, _value} -> false
    end)
  end

  defp block([expression]), do: expression
  defp block(expressions), do: {:__block__, [], expressions}
end
