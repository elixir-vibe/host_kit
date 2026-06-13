defmodule HostKit.Agent.Schedule do
  @moduledoc false

  def init(opts), do: %{every: Keyword.get(opts, :every), timer: nil, opts: opts}

  def schedule(%{every: nil} = state), do: state

  def schedule(%{every: every} = state) do
    %{state | timer: Process.send_after(self(), :run, interval_ms(every))}
  end

  def reschedule(state), do: schedule(%{state | timer: nil})

  def interval_ms(value) when is_integer(value), do: value

  def interval_ms(value) when is_binary(value) do
    {amount, unit} = Integer.parse(value)

    case unit do
      "ms" -> amount
      "s" -> amount * 1_000
      "m" -> amount * 60_000
      "h" -> amount * 3_600_000
    end
  end
end
