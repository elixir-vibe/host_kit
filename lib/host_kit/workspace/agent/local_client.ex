defmodule HostKit.Workspace.Agent.LocalClient do
  @moduledoc "Local placeholder workspace-agent client used before the Unix socket transport exists."

  @behaviour HostKit.Workspace.Agent.Client

  alias HostKit.Monitor.Result

  @impl true
  def status(socket, _opts), do: {:ok, %{socket: socket, status: :unavailable}}

  @impl true
  def exec(socket, argv, _opts), do: {:ok, %{socket: socket, argv: argv, status: :pending_agent}}

  @impl true
  def run_checks(_socket, checks, _opts) do
    {:ok, Enum.map(checks, &Result.error(&1, :pending_workspace_agent))}
  end
end
