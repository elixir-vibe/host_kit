defmodule Mix.Tasks.HostKit.Plan do
  @moduledoc "Builds and prints a HostKit plan. Pass `--local` for read-only local inspection."

  use Mix.Task

  @shortdoc "Plan HostKit resources"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional} =
      OptionParser.parse!(args,
        strict: [local: :boolean, sudo: :boolean, require: :keep, format: :string]
      )

    path = List.first(positional) || "infra/config.exs"
    project = HostKit.load!(path, require: Keyword.get_values(opts, :require))
    {:ok, plan} = HostKit.plan(project, plan_opts(opts))
    IO.puts(format_plan(plan, opts))
  end

  defp format_plan(plan, opts) do
    case Keyword.get(opts, :format, "text") do
      "text" -> HostKit.Plan.Format.format(plan)
      "inspect" -> inspect(plan, pretty: true, limit: :infinity, structs: true)
    end
  end

  defp plan_opts(opts) do
    if Keyword.get(opts, :local, false) do
      [reader: HostKit.Local, sudo: Keyword.get(opts, :sudo, false)]
    else
      []
    end
  end
end
