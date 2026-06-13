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
          ignore: :keep,
          package_lock: :string,
          write_package_lock: :string
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
    target_opts
    |> Keyword.put(:ignore, Options.ignored_resources(opts))
    |> put_package_lock(opts)
  end

  defp put_package_lock(plan_opts, opts) do
    plan_opts
    |> put_present(:package_lock, Keyword.get(opts, :package_lock))
    |> put_present(:package_lock_write, Keyword.get(opts, :write_package_lock))
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)
end
