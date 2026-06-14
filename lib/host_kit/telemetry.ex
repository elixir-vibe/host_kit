defmodule HostKit.Telemetry do
  @moduledoc "Helpers for extracting OpenTelemetry collection intent from HostKit projects."

  alias HostKit.Project
  alias HostKit.Telemetry.Signal

  @type event :: [atom()]
  @type measurements :: map()
  @type metadata :: map()

  @spec config(keyword()) :: map()
  def config(value), do: HostKit.Observability.config(value)

  @doc "Emits a HostKit telemetry event under the `[:host_kit, ...]` prefix."
  @spec execute(event(), measurements(), metadata()) :: :ok
  def execute(event, measurements \\ %{}, metadata \\ %{}) when is_list(event) do
    :telemetry.execute([:host_kit | event], measurements, metadata)
  end

  @doc "Runs a function while emitting `:start`, `:stop`, and `:exception` telemetry events."
  @spec span(event(), metadata(), (-> result)) :: result when result: term()
  def span(event, metadata \\ %{}, fun) when is_list(event) and is_function(fun, 0) do
    start_time = System.monotonic_time()
    execute(event ++ [:start], %{system_time: System.system_time()}, metadata)

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time

      execute(
        event ++ [:stop],
        %{duration: duration},
        Map.put(metadata, :result, result_status(result))
      )

      result
    catch
      kind, reason ->
        duration = System.monotonic_time() - start_time
        stacktrace = __STACKTRACE__

        execute(
          event ++ [:exception],
          %{duration: duration},
          Map.merge(metadata, %{kind: kind, reason: reason, stacktrace: stacktrace})
        )

        :erlang.raise(kind, reason, stacktrace)
    end
  end

  @spec duration_ms(integer()) :: integer()
  def duration_ms(native_duration),
    do: System.convert_time_unit(native_duration, :native, :millisecond)

  @spec signals(Project.t()) :: [Signal.t()]
  def signals(%Project{} = project) do
    project_defaults = telemetry_config(project.meta, %{})

    project.services
    |> Enum.flat_map(&service_signals(&1, project_defaults))
  end

  defp result_status({:ok, _value}), do: :ok
  defp result_status(:ok), do: :ok
  defp result_status({:error, _reason}), do: :error
  defp result_status(_other), do: :ok

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

    config
    |> Map.put(:signals, enabled_signals(config))
    |> Map.put(:resource_id, HostKit.Resource.id(resource))
    |> Signal.new()
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
