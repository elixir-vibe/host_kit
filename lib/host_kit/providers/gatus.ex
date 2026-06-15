defmodule HostKit.Providers.Gatus do
  @moduledoc "Gatus provider helpers for structured monitoring config files."

  alias HostKit.Monitor.Endpoint

  def provider_name, do: :gatus

  def dsl_modules, do: [HostKit.Providers.Gatus.DSL]

  @spec endpoints_from_monitors(HostKit.Project.t() | [HostKit.Monitor.Check.t()], keyword()) :: [
          keyword()
        ]
  def endpoints_from_monitors(project_or_checks, opts \\ []) do
    project_or_checks
    |> HostKit.Monitor.endpoint_checks(opts)
    |> sort_endpoints(opts)
    |> Enum.map(&endpoint/1)
  end

  @spec endpoint(Endpoint.t()) :: keyword()
  def endpoint(%Endpoint{} = endpoint) do
    [
      name: endpoint.name,
      group: endpoint.group,
      url: endpoint.url,
      interval: endpoint.interval,
      conditions: conditions(endpoint),
      alerts: alerts(endpoint.alerts)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)
  end

  defp sort_endpoints(endpoints, opts) do
    order = Keyword.get(opts, :order, [])

    if order == [] do
      endpoints
    else
      positions = order |> Enum.with_index() |> Map.new()

      Enum.sort_by(endpoints, fn endpoint ->
        Map.get(positions, endpoint.name, length(order))
      end)
    end
  end

  defp conditions(%Endpoint{expect: expect}) do
    [
      status_condition(Keyword.get(expect, :status, 200)),
      response_time_condition(expect)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp status_condition(status), do: "[STATUS] == #{status}"

  defp response_time_condition(expect) do
    case Keyword.get(expect, :response_time_lt) || Keyword.get(expect, :max_response_time) do
      nil -> nil
      milliseconds -> "[RESPONSE_TIME] < #{milliseconds}"
    end
  end

  defp alerts(alerts) do
    Enum.map(List.wrap(alerts), fn
      type when is_atom(type) -> [type: to_string(type)]
      type when is_binary(type) -> [type: type]
      alert when is_map(alert) -> Map.to_list(alert)
      alert when is_list(alert) -> alert
    end)
  end
end
