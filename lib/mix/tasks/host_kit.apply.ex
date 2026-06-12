defmodule Mix.Tasks.HostKit.Apply do
  @moduledoc "Applies supported HostKit plan changes. Requires `--dry-run` or `--confirm`."

  use Mix.Task

  alias Mix.Tasks.HostKit.Options

  @shortdoc "Apply HostKit resources"

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
          ignore: :keep,
          dry_run: :boolean,
          confirm: :boolean
        ],
        aliases: [dry_run: :dry_run]
      )

    path = List.first(positional) || "infra/config.exs"
    project = HostKit.load!(path, require: Keyword.get_values(opts, :require))

    Options.with_target_opts(opts, fn target_opts ->
      {:ok, plan} = HostKit.plan(project, plan_opts(opts, target_opts))

      case HostKit.apply(plan, apply_opts(opts, target_opts)) do
        {:ok, results} -> print_results(results)
        {:error, reason} -> Mix.raise("HostKit apply failed: #{inspect(reason)}")
      end
    end)
  end

  defp print_results(results) do
    results
    |> Enum.map_join("\n", fn %{change: change, status: status} ->
      "#{status} #{HostKit.Plan.Format.format_change(change)}"
    end)
    |> IO.puts()
  end

  defp plan_opts(opts, target_opts) do
    Keyword.put(target_opts, :ignore, Options.ignored_resources(opts))
  end

  defp apply_opts(opts, target_opts) do
    Keyword.merge(target_opts,
      dry_run: Keyword.get(opts, :dry_run, false),
      confirm: Keyword.get(opts, :confirm, false),
      sudo: Keyword.get(opts, :sudo, false)
    )
  end
end
