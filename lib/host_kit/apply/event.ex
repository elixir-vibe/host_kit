defmodule HostKit.Apply.Event do
  @moduledoc "Lifecycle message emitted by HostKit apply when a reporter process is configured."

  @type type ::
          :apply_started
          | :apply_finished
          | :change_started
          | :change_finished
          | :change_skipped
          | :change_failed

  @type t :: %__MODULE__{
          type: type(),
          resource_id: term(),
          action: atom() | nil,
          change: HostKit.Change.t() | nil,
          result: map() | nil,
          reason: term() | nil,
          at: DateTime.t()
        }

  defstruct [:type, :resource_id, :action, :change, :result, :reason, :at]

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

  defp resource_id(%HostKit.Change{resource_id: resource_id}), do: resource_id
  defp resource_id(_change), do: nil

  defp action(%HostKit.Change{action: action}), do: action
  defp action(_change), do: nil

  defp format_resource(%__MODULE__{resource_id: {type, name}}), do: "#{type}.#{name}"
  defp format_resource(%__MODULE__{resource_id: resource_id}), do: inspect(resource_id)

  defp format_reason(reason) do
    reason
    |> inspect(limit: 10, printable_limit: 500)
    |> truncate(1_000)
  end

  defp truncate(value, max) when byte_size(value) > max, do: binary_part(value, 0, max) <> "…"
  defp truncate(value, _max), do: value
end
