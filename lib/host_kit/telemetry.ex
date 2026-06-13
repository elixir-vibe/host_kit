defmodule HostKit.Telemetry do
  @moduledoc "Helpers for extracting OpenTelemetry collection intent from HostKit projects."

  alias HostKit.Project
  alias HostKit.Telemetry.Signal

  @spec config(keyword()) :: map()
  def config(value) when is_boolean(value), do: value

  def config(opts) do
    opts
    |> Map.new(fn
      {:attributes, attrs} -> {:attributes, Map.new(attrs)}
      pair -> pair
    end)
  end

  @spec signals(Project.t()) :: [Signal.t()]
  def signals(%Project{} = project) do
    project_defaults = telemetry_config(project.meta, %{})

    project.services
    |> Enum.flat_map(&service_signals(&1, project_defaults))
  end

  defp service_signals(service, project_defaults) do
    service_defaults = merge(project_defaults, telemetry_config(service.meta, %{}))
    Enum.flat_map(service.resources, &resource_signals(&1, service_defaults))
  end

  defp resource_signals(resource, service_defaults) do
    case telemetry_config(resource.meta, :inherit) do
      :inherit -> inherited_signal(service_defaults, resource)
      resource_config -> [signal(merge(service_defaults, resource_config), resource)]
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

  defp merge(base, false) when is_map(base), do: %{enabled: false}
  defp merge(%{enabled: false}, _override), do: %{enabled: false}
  defp merge(base, true) when is_map(base), do: Map.merge(base, normalize_config(true))

  defp merge(base, override) when is_map(base) do
    override = normalize_config(override)

    Map.merge(base, override, fn
      :attributes, left, right -> Map.merge(left, right)
      _key, _left, right -> right
    end)
  end

  defp enabled_signals(config) do
    [:logs, :metrics, :traces]
    |> Enum.filter(&(Map.get(config, &1) not in [nil, false]))
  end
end
