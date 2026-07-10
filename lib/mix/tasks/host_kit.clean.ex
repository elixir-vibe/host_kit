defmodule Mix.Tasks.HostKit.Clean do
  @moduledoc """
  Builds and optionally applies a conservative cleanup plan from HostKit release metadata.

  Cleanup uses the same target selection flags as `host_kit.plan` and the same
  confirmation model as `host_kit.apply`. Use `--dry-run` to inspect without
  deleting anything, or `--confirm` to apply the generated cleanup commands.
  """

  use Mix.Task

  alias Mix.Tasks.HostKit.{Options, Output}

  @shortdoc "Clean stale HostKit-managed release artifacts"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional} =
      OptionParser.parse!(args,
        strict: [
          local: :boolean,
          host: :string,
          remote: :string,
          user: :string,
          port: :integer,
          identity_file: :string,
          password: :string,
          password_env: :string,
          silently_accept_hosts: :boolean,
          sudo: :boolean,
          require: :keep,
          service: :keep,
          keep: :integer,
          dry_run: :boolean,
          confirm: :boolean,
          quiet: :boolean,
          verbose: :boolean
        ],
        aliases: [dry_run: :dry_run]
      )

    path = List.first(positional) || "infra/config.exs"
    project = HostKit.load!(path, require: Keyword.get_values(opts, :require))

    Options.with_target_opts(opts, project, fn target_opts ->
      case HostKit.clean(project, clean_opts(opts, target_opts)) do
        {:ok, plan} -> run_plan(plan, opts, target_opts)
        {:error, reason} -> Mix.raise("HostKit clean failed: #{inspect(reason)}")
      end
    end)
  end

  defp run_plan(plan, opts, target_opts) do
    cond do
      Keyword.get(opts, :dry_run, false) ->
        IO.puts(HostKit.format_plan(plan))

      Keyword.get(opts, :confirm, false) ->
        case HostKit.apply(plan, apply_opts(opts, target_opts)) do
          {:ok, results} -> Output.print_results(results)
          {:error, reason} -> Mix.raise("HostKit clean apply failed: #{inspect(reason)}")
        end

      true ->
        IO.puts(HostKit.format_plan(plan))
        Mix.raise("pass --dry-run to inspect or --confirm to apply cleanup")
    end
  end

  defp clean_opts(opts, target_opts) do
    target_opts
    |> Options.expand_target_opts()
    |> put_present(:services, Options.selected_services(opts))
    |> put_present(:keep, Keyword.get(opts, :keep))
  end

  defp apply_opts(opts, target_opts) do
    target_opts
    |> Options.expand_target_opts()
    |> Keyword.merge(confirm: true, dry_run: false, track: false)
    |> put_present(:keep, Keyword.get(opts, :keep))
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)
end
