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
          package_lock: :string,
          plan: :string,
          dry_run: :boolean,
          confirm: :boolean
        ],
        aliases: [dry_run: :dry_run]
      )

    Options.with_target_opts(opts, fn target_opts ->
      plan = load_plan(opts, positional, target_opts)

      case HostKit.apply(plan, apply_opts(opts, target_opts)) do
        {:ok, results} -> print_results(results)
        {:error, reason} -> Mix.raise("HostKit apply failed: #{inspect(reason)}")
      end
    end)
  end

  defp load_plan(opts, positional, target_opts) do
    case Keyword.get(opts, :plan) do
      nil ->
        path = List.first(positional) || "infra/config.exs"
        project = HostKit.load!(path, require: Keyword.get_values(opts, :require))
        {:ok, plan} = HostKit.plan(project, plan_opts(opts, target_opts))
        plan

      artifact_path ->
        case HostKit.Plan.Artifact.load(artifact_path) do
          {:ok, plan} ->
            plan

          {:error, reason} ->
            Mix.raise("could not load HostKit plan artifact: #{inspect(reason)}")
        end
    end
  end

  defp print_results(results) do
    results
    |> Enum.map_join("\n", fn %{change: change, status: status} ->
      "#{status} #{HostKit.Plan.Format.format_change(change)}"
    end)
    |> IO.puts()
  end

  defp plan_opts(opts, target_opts) do
    target_opts
    |> Keyword.put(:ignore, Options.ignored_resources(opts))
    |> put_present(:package_lock, Keyword.get(opts, :package_lock))
  end

  defp apply_opts(opts, target_opts) do
    Keyword.merge(target_opts,
      dry_run: Keyword.get(opts, :dry_run, false),
      confirm: Keyword.get(opts, :confirm, false),
      sudo: Keyword.get(opts, :sudo, false)
    )
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)
end
