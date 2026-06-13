defmodule HostKit.Agent.State do
  @moduledoc false

  use GenServer

  @initial_state %{
    started_at: nil,
    project: nil,
    target: nil,
    last_plan: nil,
    last_apply: nil,
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

  def handle_call({:configure, opts}, _from, state) do
    state =
      state
      |> maybe_put(:project, Keyword.get(opts, :project))
      |> maybe_put(:target, Keyword.get(opts, :target))
      |> put_event(:configured)

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
      events: state.events
    }
  end

  defp maybe_put(state, _key, nil), do: state
  defp maybe_put(state, key, value), do: Map.put(state, key, value)

  defp put_event(state, event) do
    event = %{at: DateTime.utc_now(), event: event}
    Map.update!(state, :events, &[event | Enum.take(&1, 49)])
  end

  defp project_name(%HostKit.Project{name: name}), do: name
  defp project_name(_project), do: nil

  defp target_name(%HostKit.Target{name: name}), do: name
  defp target_name(_target), do: nil
end
