defmodule Mix.Tasks.HostKit.Plan do
  @moduledoc "Builds and prints a structural HostKit plan."

  use Mix.Task

  @shortdoc "Plan HostKit resources"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    path = List.first(args) || "infra/config.exs"
    project = HostKit.load!(path)
    {:ok, plan} = HostKit.plan(project)
    IO.inspect(plan, pretty: true, limit: :infinity, structs: true)
  end
end
