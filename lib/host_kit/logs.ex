defmodule HostKit.Logs do
  @moduledoc "Helpers for extracting log management declarations from HostKit projects."

  alias HostKit.Logs.Config
  alias HostKit.Project

  @spec config(keyword() | boolean()) :: map() | boolean()
  def config(value), do: HostKit.Observability.config(value)

  @spec configs(Project.t()) :: [Config.t()]
  def configs(%Project{} = project) do
    project_defaults = logs_config(project.meta, %{})

    project.services
    |> Enum.flat_map(&service_configs(&1, project_defaults))
  end

  defp service_configs(service, project_defaults) do
    service_defaults = merge_config(project_defaults, logs_config(service.meta, %{}))
    Enum.flat_map(service.resources, &resource_configs(&1, service_defaults))
  end

  defp resource_configs(resource, service_defaults) do
    case logs_config(resource.meta, :inherit) do
      :inherit ->
        inherited_config(service_defaults, resource)

      resource_config ->
        [config_struct(merge_config(service_defaults, resource_config), resource)]
    end
  end

  defp inherited_config(%{enabled: false}, _resource), do: []
  defp inherited_config(%{} = config, _resource) when map_size(config) == 0, do: []
  defp inherited_config(%{} = config, resource), do: [config_struct(config, resource)]

  defp logs_config(meta, default) do
    meta
    |> Map.get(:observability, %{})
    |> Map.get(:logs, Map.get(meta, :logs, default))
  end

  defp config_struct(config, resource) do
    config = normalize_config(config)

    %Config{
      driver: Map.get(config, :driver),
      source: Map.get(config, :source),
      identifier: Map.get(config, :identifier),
      format: Map.get(config, :format),
      retention: Map.get(config, :retention),
      max_use: Map.get(config, :max_use),
      rotate: Map.get(config, :rotate, []),
      ship: Map.get(config, :ship),
      sensitive: Map.get(config, :sensitive, false),
      stdout: Map.get(config, :stdout),
      stderr: Map.get(config, :stderr),
      attributes: Map.get(config, :attributes, %{}),
      resource_id: HostKit.Resource.id(resource),
      meta: Map.get(config, :meta, %{})
    }
  end

  defp normalize_config(false), do: %{enabled: false}
  defp normalize_config(true), do: %{driver: :journald, ship: true}
  defp normalize_config(config) when is_list(config), do: config(config)
  defp normalize_config(config) when is_map(config), do: config

  defp merge_config(base, override),
    do: HostKit.Observability.merge(base, override, &normalize_config/1)
end
