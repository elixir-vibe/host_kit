defmodule HostKit.Agent.DriftWorker do
  @moduledoc "Supervised worker for scheduled drift planning."

  use GenServer

  alias HostKit.Agent.{Schedule, State}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec run_once(keyword()) :: {:ok, HostKit.Plan.t()} | {:error, term()}
  def run_once(opts \\ []) do
    opts
    |> run_plan()
    |> tap(&State.record_plan/1)
  end

  @impl true
  def init(opts) do
    {:ok, opts |> Schedule.init() |> Schedule.schedule()}
  end

  @impl true
  def handle_info(:run, state) do
    run_once(state.opts)
    {:noreply, Schedule.reschedule(state)}
  end

  defp run_plan(opts) do
    snapshot = State.snapshot()

    case snapshot.project do
      nil ->
        {:error, :agent_not_configured}

      project ->
        plan_opts =
          opts |> Keyword.get(:plan_opts, []) |> Keyword.put_new(:target, snapshot.target)

        HostKit.plan(project, plan_opts)
    end
  end
end
