defmodule HostKit.Agent.State do
  @moduledoc false

  use GenServer

  @initial_state %{
    started_at: nil,
    project: nil,
    target: nil,
    last_plan: nil,
    last_apply: nil,
    last_monitor: nil,
    events: []
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  def configure(opts) do
    GenServer.call(__MODULE__, {:configure, opts})
  end

  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  def record_monitor(result) do
    GenServer.call(__MODULE__, {:record_monitor, result})
  end

  def record_event(event) do
    GenServer.cast(__MODULE__, {:record_event, event})
  end

  @impl true
  def init(_opts) do
    {:ok, %{@initial_state | started_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, public_status(state), state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:reset, _from, _state) do
    state = %{@initial_state | started_at: DateTime.utc_now()}
    {:reply, :ok, state}
  end

  def handle_call({:configure, opts}, _from, state) do
    state =
      state
      |> maybe_put(:project, Keyword.get(opts, :project))
      |> maybe_put(:target, Keyword.get(opts, :target))
      |> put_event(:configured)

    {:reply, :ok, state}
  end

  def handle_call({:record_monitor, result}, _from, state) do
    state =
      state
      |> Map.put(:last_monitor, result)
      |> put_event({:monitor_completed, monitor_summary(result)})

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:record_event, event}, state) do
    {:noreply, put_event(state, event)}
  end

  defp public_status(state) do
    %{
      started_at: state.started_at,
      configured?: state.project != nil,
      project: project_name(state.project),
      target: target_name(state.target),
      last_plan: state.last_plan,
      last_apply: state.last_apply,
      last_monitor: state.last_monitor,
      events: state.events
    }
  end

  defp maybe_put(state, _key, nil), do: state
  defp maybe_put(state, key, value), do: Map.put(state, key, value)

  defp monitor_summary({:ok, results}) do
    %{
      ok: Enum.count(results, &(&1.status == :ok)),
      error: Enum.count(results, &(&1.status == :error))
    }
  end

  defp monitor_summary({:error, reason}), do: %{error: reason}

  defp put_event(state, event) do
    event = %{at: DateTime.utc_now(), event: event}
    Map.update!(state, :events, &[event | Enum.take(&1, 49)])
  end

  defp project_name(%HostKit.Project{name: name}), do: name
  defp project_name(_project), do: nil

  defp target_name(%HostKit.Target{name: name}), do: name
  defp target_name(_target), do: nil
end
