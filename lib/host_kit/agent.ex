defmodule HostKit.Agent do
  @moduledoc "Runtime API for the optional HostKit host agent."

  alias HostKit.Agent.State

  @spec status() :: map()
  def status, do: State.status()

  @spec configure(keyword()) :: :ok
  def configure(opts), do: State.configure(opts)

  @spec snapshot() :: map()
  def snapshot, do: State.snapshot()

  @spec reset() :: :ok
  def reset, do: State.reset()

  @spec record_plan(term()) :: :ok
  def record_plan(result), do: State.record_plan(result)

  @spec record_monitor(term()) :: :ok
  def record_monitor(result), do: State.record_monitor(result)

  @spec run_plan(keyword()) :: {:ok, HostKit.Plan.t()} | {:error, term()}
  def run_plan(opts \\ []), do: HostKit.Agent.DriftWorker.run_once(opts)

  @spec run_monitor(keyword()) :: {:ok, [HostKit.Monitor.Result.t()]} | {:error, term()}
  def run_monitor(opts \\ []), do: HostKit.Agent.MonitorWorker.run_once(opts)

  @spec record_event(term()) :: :ok
  def record_event(event), do: State.record_event(event)
end
