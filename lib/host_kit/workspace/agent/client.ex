defmodule HostKit.Workspace.Agent.Client do
  @moduledoc "Client boundary for communicating with workspace agents."

  alias HostKit.Monitor

  @callback status(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback exec(String.t(), [String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  @callback run_checks(String.t(), [Monitor.Check.t()], keyword()) ::
              {:ok, [Monitor.Result.t()]} | {:error, term()}
end
