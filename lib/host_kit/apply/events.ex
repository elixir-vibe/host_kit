defmodule HostKit.Apply.Events do
  @moduledoc false

  require Logger

  alias HostKit.Apply.Event

  @logged_by_default MapSet.new([
                       :transport_retry_started,
                       :transport_retry_succeeded,
                       :transport_retry_exhausted
                     ])

  @spec emit(keyword(), Event.type(), keyword()) :: :ok
  def emit(opts, type, attrs \\ []) do
    event = Event.new(type, attrs)

    emit_mailbox(opts, event)
    emit_telemetry(event)
    maybe_log(opts, event)

    :ok
  end

  defp emit_mailbox(opts, event) do
    case Keyword.get(opts, :reporter) do
      pid when is_pid(pid) -> send(pid, {HostKit.Apply, event})
      _other -> :ok
    end
  end

  defp emit_telemetry(%Event{} = event) do
    HostKit.Telemetry.execute(
      [:apply, :event],
      %{system_time: System.system_time()},
      %{
        type: event.type,
        resource_id: event.resource_id,
        action: event.action,
        details: event.details
      }
    )
  end

  defp maybe_log(opts, %Event{} = event) do
    if log_event?(opts, event.type) do
      Logger.log(log_level(event.type), Event.format(event), log_metadata(event))
    end
  end

  defp log_event?(opts, type) do
    Keyword.get(opts, :log_events, false) or MapSet.member?(@logged_by_default, type)
  end

  defp log_level(:transport_retry_started), do: :warning
  defp log_level(:transport_retry_succeeded), do: :info
  defp log_level(:transport_retry_exhausted), do: :error
  defp log_level(:change_failed), do: :error
  defp log_level(:readiness_failed), do: :error
  defp log_level(:service_failed), do: :error
  defp log_level(:health_check_failed), do: :error
  defp log_level(_type), do: :info

  defp log_metadata(%Event{} = event) do
    [
      hostkit_event: event.type,
      resource_id: event.resource_id,
      action: event.action,
      reason: inspect(event.reason || Map.get(event.details, :reason)),
      details: event.details
    ]
  end
end
