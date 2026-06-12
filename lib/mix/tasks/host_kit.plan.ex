defmodule Mix.Tasks.HostKit.Plan do
  @moduledoc "Builds and prints a HostKit plan. Pass `--local` for read-only local inspection."

  use Mix.Task

  alias Mix.Tasks.HostKit.Options

  @shortdoc "Plan HostKit resources"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional} =
      OptionParser.parse!(args,
        strict: [
          local: :boolean,
          remote: :string,
          user: :string,
          port: :integer,
          sudo: :boolean,
          require: :keep,
          format: :string,
          ignore: :keep
        ]
      )

    path = List.first(positional) || "infra/config.exs"
    project = HostKit.load!(path, require: Keyword.get_values(opts, :require))

    Options.with_target_opts(opts, fn target_opts ->
      {:ok, plan} = HostKit.plan(project, plan_opts(opts, target_opts))
      IO.puts(format_plan(plan, opts))
    end)
  end

  defp format_plan(plan, opts) do
    case Keyword.get(opts, :format, "text") do
      "text" -> HostKit.Plan.Format.format(plan)
      "inspect" -> inspect(plan, pretty: true, limit: :infinity, structs: true)
    end
  end

  defp plan_opts(opts, target_opts) do
    Keyword.put(target_opts, :ignore, Options.ignored_resources(opts))
  end
end
