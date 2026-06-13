defmodule HostKit.Supervisor do
  @moduledoc "Top-level HostKit supervision tree."

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    children = [
      HostKit.Agent.State,
      {HostKit.Agent.MonitorWorker, Keyword.get(opts, :monitor, [])}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
