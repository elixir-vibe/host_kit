defmodule HostKit.Agent do
  @moduledoc "Runtime API for the optional HostKit host agent."

  alias HostKit.Agent.State

  @spec status() :: map()
  def status, do: State.status()

  @spec configure(keyword()) :: :ok
  def configure(opts), do: State.configure(opts)

  @spec record_event(term()) :: :ok
  def record_event(event), do: State.record_event(event)
end
