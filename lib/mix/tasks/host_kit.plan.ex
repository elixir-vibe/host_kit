defmodule Mix.Tasks.HostKit.Plan do
  @moduledoc "Builds and prints a HostKit plan. Pass `--local` for read-only local inspection."

  use Mix.Task

  @shortdoc "Plan HostKit resources"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional} = OptionParser.parse!(args, strict: [local: :boolean])
    path = List.first(positional) || "infra/config.exs"
    project = HostKit.load!(path)
    plan_opts = if Keyword.get(opts, :local, false), do: [reader: HostKit.Local], else: []
    {:ok, plan} = HostKit.plan(project, plan_opts)
    plan |> inspect(pretty: true, limit: :infinity, structs: true) |> IO.puts()
  end
end
