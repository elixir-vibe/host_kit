defmodule HostKit.Telemetry do
  @moduledoc "Helpers for extracting OpenTelemetry collection intent from HostKit projects."

  alias HostKit.Project
  alias HostKit.Telemetry.Signal

  @spec config(keyword()) :: map()
  def config(value), do: HostKit.Observability.config(value)

  @spec signals(Project.t()) :: [Signal.t()]
  def signals(%Project{} = project) do
    project_defaults = telemetry_config(project.meta, %{})

    project.services
    |> Enum.flat_map(&service_signals(&1, project_defaults))
  end

  defp service_signals(service, project_defaults) do
    service_defaults = merge_config(project_defaults, telemetry_config(service.meta, %{}))
    Enum.flat_map(service.resources, &resource_signals(&1, service_defaults))
  end

  defp resource_signals(resource, service_defaults) do
    case telemetry_config(resource.meta, :inherit) do
      :inherit -> inherited_signal(service_defaults, resource)
      resource_config -> [signal(merge_config(service_defaults, resource_config), resource)]
    end
  end

  defp inherited_signal(%{enabled: false}, _resource), do: []

  defp inherited_signal(%{} = config, resource) when map_size(config) == 0,
    do: resource_signal(resource, %{})

  defp inherited_signal(%{} = config, resource), do: [signal(config, resource)]

  defp resource_signal(%HostKit.Systemd.Service{} = resource, _config) do
    [%{logs: :journald, metrics: :systemd} |> signal(resource)]
  end

  defp resource_signal(%HostKit.Caddy.Site{} = resource, _config) do
    [%{logs: :access, metrics: :http} |> signal(resource)]
  end

  defp resource_signal(_resource, _config), do: []

  defp telemetry_config(meta, default) do
    meta
    |> Map.get(:observability, %{})
    |> Map.get(:telemetry, Map.get(meta, :telemetry, default))
  end

  defp signal(config, resource) do
    config = normalize_config(config)

    %Signal{
      service_name: Map.get(config, :service_name),
      signals: enabled_signals(config),
      logs: Map.get(config, :logs),
      metrics: Map.get(config, :metrics),
      traces: Map.get(config, :traces),
      attributes: Map.get(config, :attributes, %{}),
      resource_id: HostKit.Resource.id(resource),
      meta: Map.get(config, :meta, %{})
    }
  end

  defp normalize_config(false), do: %{enabled: false}
  defp normalize_config(true), do: %{logs: true, metrics: true, traces: false}
  defp normalize_config(config) when is_list(config), do: config(config)
  defp normalize_config(config) when is_map(config), do: config

  defp merge_config(base, override),
    do: HostKit.Observability.merge(base, override, &normalize_config/1)

  defp enabled_signals(config) do
    [:logs, :metrics, :traces]
    |> Enum.filter(&(Map.get(config, &1) not in [nil, false]))
  end
end
