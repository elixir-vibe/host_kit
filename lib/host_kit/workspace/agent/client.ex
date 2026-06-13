defmodule HostKit.Workspace.Agent.Client do
  @moduledoc "Client boundary for communicating with workspace agents."

  alias HostKit.Monitor

  @callback status(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback exec(String.t(), [String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  @callback run_checks(String.t(), [Monitor.Check.t()], keyword()) ::
              {:ok, [Monitor.Result.t()]} | {:error, term()}

  def status(socket, opts \\ []) do
    client(opts).status(socket, opts)
  end

  def exec(socket, argv, opts \\ []) do
    client(opts).exec(socket, argv, opts)
  end

  def run_checks(socket, checks, opts \\ []) do
    client(opts).run_checks(socket, checks, opts)
  end

  defp client(opts), do: Keyword.get(opts, :client, HostKit.Workspace.Agent.LocalClient)
end
