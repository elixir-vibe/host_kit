defmodule HostKit.Runner.Local do
  @moduledoc "Local command runner for HostKit operations."

  @behaviour HostKit.Runner

  @impl true
  def cmd(command, args, opts \\ []) do
    System.cmd(command, args, opts)
  end
end
