defmodule HostKit.Apply.Event do
  @moduledoc "Lifecycle message emitted by HostKit apply when a reporter process is configured."

  @type type ::
          :apply_started
          | :apply_finished
          | :change_started
          | :change_finished
          | :change_skipped
          | :change_failed
          | :readiness_started
          | :readiness_waiting
          | :readiness_passed
          | :readiness_failed
          | :service_restart_started
          | :service_restart_finished
          | :service_active
          | :service_failed
          | :health_check_started
          | :health_check_waiting
          | :health_check_passed
          | :health_check_failed
          | :transport_retry_started
          | :transport_retry_succeeded
          | :transport_retry_exhausted

  @type t :: %__MODULE__{
          type: type(),
          resource_id: term(),
          action: atom() | nil,
          change: HostKit.Change.t() | nil,
          result: map() | nil,
          reason: term() | nil,
          lifecycle: map() | nil,
          details: map(),
          at: DateTime.t()
        }

  defstruct [
    :type,
    :resource_id,
    :action,
    :change,
    :result,
    :reason,
    :lifecycle,
    details: %{},
    at: nil
  ]

  @spec new(type(), keyword()) :: t()
  def new(type, attrs \\ []) do
    change = Keyword.get(attrs, :change)

    %__MODULE__{
      type: type,
      resource_id: Keyword.get(attrs, :resource_id, resource_id(change)),
      action: Keyword.get(attrs, :action, action(change)),
      change: change,
      result: Keyword.get(attrs, :result),
      reason: Keyword.get(attrs, :reason),
      lifecycle: Keyword.get(attrs, :lifecycle),
      details: Keyword.get(attrs, :details, %{}),
      at: DateTime.utc_now()
    }
  end

  @spec format(t()) :: String.t()
  def format(%__MODULE__{type: :apply_started}), do: "▶ applying HostKit plan"
  def format(%__MODULE__{type: :apply_finished}), do: "✓ apply finished"

  def format(%__MODULE__{type: :change_started} = event),
    do: "▶ #{format_resource(event)} #{event.action}"

  def format(%__MODULE__{type: :change_finished} = event),
    do: "✓ #{format_resource(event)} #{event.action}"

  def format(%__MODULE__{type: :change_skipped} = event),
    do: "⏭ #{format_resource(event)} #{event.action}"

  def format(%__MODULE__{type: :change_failed} = event),
    do: "✗ #{format_resource(event)} #{event.action}: #{format_reason(event.reason)}"

  def format(%__MODULE__{type: :readiness_started} = event),
    do: "▶ readiness #{format_resource(event)}"

  def format(%__MODULE__{type: :readiness_waiting, details: details}),
    do:
      "↻ readiness waiting #{format_progress(details)}: #{Map.get(details, :summary, "not ready")}"

  def format(%__MODULE__{type: :readiness_passed} = event),
    do: "✓ readiness #{format_resource(event)}"

  def format(%__MODULE__{type: :readiness_failed} = event),
    do: "✗ readiness #{format_resource(event)}: #{format_reason(event.reason)}"

  def format(%__MODULE__{type: :service_restart_started, details: details}),
    do: "↻ restarting #{Map.get(details, :unit)}"

  def format(%__MODULE__{type: :service_restart_finished, details: details}),
    do: "✓ restarted #{Map.get(details, :unit)}"

  def format(%__MODULE__{type: :service_active, details: details}),
    do: "✓ service active #{Map.get(details, :unit)}"

  def format(%__MODULE__{type: :service_failed, details: details} = event),
    do: "✗ service #{Map.get(details, :unit)}: #{format_reason(event.reason)}"

  def format(%__MODULE__{type: :health_check_started, details: details}),
    do: "▶ health check #{Map.get(details, :url)}"

  def format(%__MODULE__{type: :health_check_waiting, details: details}),
    do: "↻ health check waiting #{Map.get(details, :url)} #{format_progress(details)}"

  def format(%__MODULE__{type: :health_check_passed, details: details}),
    do: "✓ health check passed #{Map.get(details, :url)}"

  def format(%__MODULE__{type: :health_check_failed, details: details} = event),
    do: "✗ health check #{Map.get(details, :url)}: #{format_reason(event.reason)}"

  def format(%__MODULE__{type: :transport_retry_started, details: details}) do
    suffix = "after #{Map.fetch!(details, :delay_ms)}ms"
    format_transport_retry("↻", "reconnect", details, suffix)
  end

  def format(%__MODULE__{type: :transport_retry_succeeded, details: details}) do
    format_transport_retry("✓", "reconnect", details)
  end

  def format(%__MODULE__{type: :transport_retry_exhausted, details: details} = event) do
    suffix = "attempts exhausted: #{format_reason(Map.get(details, :reason) || event.reason)}"
    format_transport_retry("✗", "reconnect", details, suffix)
  end

  defp resource_id(%HostKit.Change{resource_id: resource_id}), do: resource_id
  defp resource_id(_change), do: nil

  defp action(%HostKit.Change{action: action}), do: action
  defp action(_change), do: nil

  defp format_resource(%__MODULE__{resource_id: {type, name}}), do: "#{type}.#{name}"
  defp format_resource(%__MODULE__{resource_id: resource_id}), do: inspect(resource_id)

  defp format_transport_retry(prefix, action, details, suffix \\ nil) do
    base =
      "#{prefix} #{Map.fetch!(details, :transport)} #{action} attempt=#{Map.fetch!(details, :attempt)}/#{Map.fetch!(details, :attempts)}"

    if suffix, do: base <> " " <> suffix, else: base
  end

  defp format_progress(%{elapsed_ms: elapsed, timeout_ms: timeout, attempt: attempt}) do
    "attempt=#{attempt} #{div(elapsed, 1_000)}s/#{div(timeout, 1_000)}s"
  end

  defp format_progress(_details), do: ""

  defp format_reason(reason), do: HostKit.Error.format(reason, max: 1_000)
end
