defmodule Mix.Tasks.HostKit.Apply do
  @moduledoc "Applies supported HostKit plan changes. Requires `--dry-run` or `--confirm`."

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
          remote: :string,
          user: :string,
          port: :integer,
          identity_file: :string,
          password: :string,
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
      sudo: Keyword.get(opts, :sudo, false)
    )
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)
end
