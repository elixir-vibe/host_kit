defmodule HostKit.Agent.MonitorWorker do
  @moduledoc "Supervised worker for scheduled monitoring checks."

  use GenServer

  alias HostKit.Agent.State

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec run_once(keyword()) :: {:ok, [HostKit.Monitor.Result.t()]} | {:error, term()}
  def run_once(opts \\ []) do
    opts
    |> run_monitor()
    |> tap(&State.record_monitor/1)
  end

  @impl true
  def init(opts) do
    state = %{every: Keyword.get(opts, :every), timer: nil, opts: opts}
    {:ok, schedule(state)}
  end

  @impl true
  def handle_info(:run, state) do
    run_once(state.opts)
    {:noreply, schedule(%{state | timer: nil})}
  end

  defp run_monitor(opts) do
    snapshot = State.snapshot()

    case snapshot.project do
      nil ->
        {:error, :agent_not_configured}

      project ->
        monitor_opts =
          opts |> Keyword.get(:monitor_opts, []) |> Keyword.put_new(:target, snapshot.target)

        HostKit.Monitor.run(project, monitor_opts)
    end
  end

  defp schedule(%{every: nil} = state), do: state

  defp schedule(%{every: every} = state) do
    %{state | timer: Process.send_after(self(), :run, interval_ms(every))}
  end

  defp interval_ms(value) when is_integer(value), do: value

  defp interval_ms(value) when is_binary(value) do
    {amount, unit} = Integer.parse(value)

    case unit do
      "ms" -> amount
      "s" -> amount * 1_000
      "m" -> amount * 60_000
      "h" -> amount * 3_600_000
    end
  end
end
