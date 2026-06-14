defmodule Mix.Tasks.HostKit.Apply do
  @moduledoc """
  Applies supported HostKit plan changes. Requires `--dry-run` or `--confirm`.

  Prefer `--host NAME config.exs` for remote targets declared with HostKit's
  `host` DSL. Raw SSH flags (`--remote`, `--user`, `--port`, `--identity-file`,
  `--password-env`) are available as an escape hatch.
  """

  use Mix.Task

  alias HostKit.Package.{Manager, TargetRepo}
  alias Mix.Tasks.HostKit.Options

  @shortdoc "Apply HostKit resources"

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
          ignore: :keep,
          package_lock: :string,
          plan: :string,
          repology_cache: :string,
          repology_cache_ttl: :integer,
          repology_no_cache: :boolean,
          dry_run: :boolean,
          confirm: :boolean,
          track: :boolean,
          runs_root: :string,
          quiet: :boolean,
          verbose: :boolean
        ],
        aliases: [dry_run: :dry_run]
      )

    project = load_project(opts, positional)

    Options.with_target_opts(opts, project, fn target_opts ->
      plan = load_plan(opts, project, positional, target_opts)
      reporter = start_reporter(opts)

      try do
        case HostKit.apply(plan, Keyword.put(apply_opts(opts, target_opts), :reporter, reporter)) do
          {:ok, results} -> print_results(results)
          {:error, reason} -> Mix.raise("HostKit apply failed: #{inspect(reason)}")
        end
      after
        send(reporter, :stop)
      end
    end)
  end

  defp load_project(opts, positional) do
    if Keyword.has_key?(opts, :plan) && !Keyword.has_key?(opts, :host) do
      nil
    else
      path = List.first(positional) || "infra/config.exs"
      HostKit.load!(path, require: Keyword.get_values(opts, :require))
    end
  end

  defp load_plan(opts, project, positional, target_opts) do
    case Keyword.get(opts, :plan) do
      nil ->
        project = project || HostKit.load!(List.first(positional) || "infra/config.exs")

        case HostKit.plan(project, plan_opts(opts, target_opts)) do
          {:ok, plan} ->
            plan

          {:error, %HostKit.Diagnostics{} = diagnostics} ->
            Mix.raise(HostKit.Diagnostics.Format.format(diagnostics))

          {:error, reason} ->
            Mix.raise("HostKit plan failed: #{inspect(reason)}")
        end

      artifact_path ->
        target_opts = expand_target_opts(target_opts)

        with {:ok, artifact} <- HostKit.Plan.Artifact.load_artifact(artifact_path),
             :ok <- validate_artifact_target(artifact, target_opts),
             {:ok, plan} <- HostKit.Plan.Artifact.to_plan(artifact) do
          plan
        else
          {:error, reason} ->
            Mix.raise("could not load HostKit plan artifact: #{inspect(reason)}")
        end
    end
  end

  defp validate_artifact_target(%HostKit.Plan.Artifact{target: target}, target_opts)
       when is_map(target) do
    with :ok <- validate_package_repo(target, target_opts) do
      validate_package_manager(target, target_opts)
    end
  end

  defp validate_artifact_target(_artifact, _target_opts), do: :ok

  defp validate_package_repo(%{"package_repo" => expected}, target_opts)
       when is_binary(expected) do
    actual =
      case Keyword.get(target_opts, :package_repo) do
        repo when is_binary(repo) -> {:ok, repo}
        _other -> TargetRepo.detect(target_opts)
      end

    case actual do
      {:ok, ^expected} ->
        :ok

      {:ok, actual} ->
        {:error, {:plan_artifact_target_mismatch, :package_repo, expected, actual}}

      {:error, reason} ->
        {:error, {:plan_artifact_target_detection_failed, :package_repo, reason}}
    end
  end

  defp validate_package_repo(_target, _target_opts), do: :ok

  defp validate_package_manager(%{"package_manager" => expected}, target_opts)
       when is_binary(expected) do
    case Manager.resolve(target_opts) do
      {:ok, manager} ->
        actual = to_string(manager)

        if actual == expected do
          :ok
        else
          {:error, {:plan_artifact_target_mismatch, :package_manager, expected, actual}}
        end

      {:error, reason} ->
        {:error, {:plan_artifact_target_detection_failed, :package_manager, reason}}
    end
  end

  defp validate_package_manager(_target, _target_opts), do: :ok

  defp expand_target_opts(opts) do
    case Keyword.pop(opts, :target) do
      {%HostKit.Target{} = target, opts} -> HostKit.Target.opts(target, opts)
      {nil, opts} -> opts
    end
  end

  defp start_reporter(opts) do
    spawn(fn ->
      reporter_loop(%{
        quiet: Keyword.get(opts, :quiet, false),
        verbose: Keyword.get(opts, :verbose, false)
      })
    end)
  end

  defp reporter_loop(opts) do
    receive do
      {HostKit.Apply, %HostKit.Apply.Event{} = event} ->
        if print_event?(event, opts), do: IO.puts(HostKit.Apply.Event.format(event))
        reporter_loop(opts)

      :stop ->
        :ok
    end
  end

  defp print_event?(_event, %{verbose: true}), do: true
  defp print_event?(%HostKit.Apply.Event{type: :change_skipped}, _opts), do: false

  defp print_event?(%HostKit.Apply.Event{type: type}, %{quiet: true}),
    do:
      type in [
        :apply_started,
        :apply_finished,
        :change_failed,
        :readiness_failed,
        :service_failed,
        :health_check_failed
      ]

  defp print_event?(_event, _opts), do: true

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
    |> Options.put_repology_cache(opts)
  end

  defp apply_opts(opts, target_opts) do
    Keyword.merge(target_opts,
      dry_run: Keyword.get(opts, :dry_run, false),
      confirm: Keyword.get(opts, :confirm, false),
      sudo: Keyword.get(opts, :sudo, Keyword.get(target_opts, :sudo, false)),
      track: Keyword.get(opts, :track, false)
    )
    |> put_present(:hostkit_runs_root, Keyword.get(opts, :runs_root))
    |> put_present(:up_plan_artifact, Keyword.get(opts, :plan))
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)
end
