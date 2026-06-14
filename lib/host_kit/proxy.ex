defmodule HostKit.Proxy do
  @moduledoc "Generic proxy desired-state resource."

  @type t :: %__MODULE__{
          name: atom(),
          provider: atom(),
          path: String.t(),
          state: String.t() | nil,
          listeners: [map()],
          acme: keyword() | nil,
          services: [map()],
          meta: map()
        }

  defstruct [
    :name,
    :provider,
    path: "/etc/gatehouse/config.exs",
    state: nil,
    listeners: [],
    acme: nil,
    services: [],
    meta: %{}
  ]

  def id(%__MODULE__{name: name}), do: {:proxy, name}

  def service(name, opts \\ []) do
    %{
      name: name,
      hosts: [],
      targets: [],
      balance: nil,
      health: nil,
      drain: nil,
      tls: nil,
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def render(%__MODULE__{} = proxy) do
    proxy
    |> to_quoted()
    |> Code.quoted_to_algebra()
    |> Inspect.Algebra.format(:infinity)
    |> IO.iodata_to_binary()
  end

  def to_quoted(%__MODULE__{provider: :gatehouse} = proxy) do
    expressions =
      [import_gatehouse_config()]
      |> maybe_append(proxy.state && {:state, [], [proxy.state]})
      |> maybe_append(proxy.acme && {:acme, [], [proxy.acme]})
      |> Kernel.++(Enum.map(proxy.listeners, &listener_quoted/1))
      |> Kernel.++(Enum.map(proxy.services, &gatehouse_service_quoted/1))

    block(expressions)
  end

  def to_quoted(%__MODULE__{provider: provider}) do
    raise ArgumentError, "unsupported proxy provider #{inspect(provider)}"
  end

  defp import_gatehouse_config do
    {:import, [], [{:__aliases__, [], [:Gatehouse, :Config]}]}
  end

  defp listener_quoted(%{scheme: scheme, opts: opts}) when scheme in [:http, :https] do
    {scheme, [], [opts]}
  end

  defp gatehouse_service_quoted(service) do
    expressions =
      Enum.map(service.hosts, &host_quoted/1) ++
        Enum.map(service.targets, &target_quoted/1) ++
        optional_service_directives(service)

    {:service, [], [service.name, [do: block(expressions)]]}
  end

  defp optional_service_directives(service) do
    []
    |> maybe_append(service[:balance] && {:balance, [], balance_args(service.balance)})
    |> maybe_append(service[:health] && {:health, [], health_args(service.health)})
    |> maybe_append(service[:drain] && {:drain, [], [service.drain]})
    |> maybe_append(not is_nil(service[:tls]) && {:tls, [], [service.tls]})
  end

  defp balance_args(%{policy: policy, opts: opts}), do: [policy, opts]
  defp health_args(%{path: path, opts: opts}), do: [path, opts]

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

  defp maybe_append(list, nil), do: list
  defp maybe_append(list, false), do: list
  defp maybe_append(list, expression), do: list ++ [expression]

  defp block([expression]), do: expression
  defp block(expressions), do: {:__block__, [], expressions}
end
