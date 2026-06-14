defmodule Mix.Tasks.HostKit.Plan do
  @moduledoc """
  Builds and prints a HostKit plan.

  Prefer `--host NAME config.exs` for remote targets declared with HostKit's
  `host` DSL. Raw SSH flags (`--remote`, `--user`, `--port`, `--identity-file`,
  `--password-env`) are available as an escape hatch.

  Pass `--local` for read-only local inspection.
  """

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
          format: :string,
          out: :string,
          ignore: :keep,
          package_lock: :string,
          write_package_lock: :string,
          repology_cache: :string,
          repology_cache_ttl: :integer,
          repology_no_cache: :boolean
        ]
      )

    path = List.first(positional) || "infra/config.exs"
    project = HostKit.load!(path, require: Keyword.get_values(opts, :require))

    Options.with_target_opts(opts, project, fn target_opts ->
      case HostKit.plan(project, plan_opts(opts, target_opts)) do
        {:ok, plan} ->
          maybe_write_artifact(plan, opts, target_opts)
          IO.puts(Mix.Tasks.HostKit.Output.format_plan(plan, opts))

        {:error, %HostKit.Diagnostics{} = diagnostics} ->
          Mix.raise(HostKit.Diagnostics.Format.format(diagnostics))

        {:error, reason} ->
          Mix.raise("HostKit plan failed: #{inspect(reason)}")
      end
    end)
  end

  defp maybe_write_artifact(plan, opts, target_opts) do
    case Keyword.get(opts, :out) do
      nil ->
        :ok

      path ->
        case HostKit.Plan.Artifact.save(path, plan,
               target_metadata: target_metadata(plan, opts, target_opts)
             ) do
          :ok ->
            :ok

          {:error, reason} ->
            Mix.raise("could not write HostKit plan artifact: #{inspect(reason)}")
        end
    end
  end

  defp target_metadata(plan, _opts, target_opts) do
    %{}
    |> put_metadata("kind", target_kind(target_opts))
    |> put_metadata("package_manager", package_manager(plan, target_opts))
    |> put_metadata("package_repo", package_repo(plan, target_opts))
  end

  defp target_kind(target_opts) do
    cond do
      Keyword.has_key?(target_opts, :target) -> "remote"
      Keyword.get(target_opts, :reader) == HostKit.Local -> "local"
      true -> nil
    end
  end

  defp package_manager(plan, target_opts) do
    plan.opts
    |> Keyword.get(:package_manager, Keyword.get(target_opts, :package_manager))
    |> case do
      nil -> nil
      manager -> to_string(manager)
    end
  end

  defp package_repo(plan, target_opts) do
    case Keyword.get(target_opts, :package_repo) do
      repo when is_binary(repo) -> resolved_package_repo(repo)
      _other -> resolved_package_repo(plan)
    end
  end

  defp resolved_package_repo(repo) when is_binary(repo), do: repo

  defp resolved_package_repo(plan) do
    plan.resources
    |> Enum.flat_map(fn
      %HostKit.Resources.Package{meta: %{resolution: %{repo: repo}}} when is_binary(repo) ->
        [repo]

      _resource ->
        []
    end)
    |> Enum.uniq()
    |> case do
      [repo] -> repo
      _other -> nil
    end
  end

  defp put_metadata(metadata, _key, nil), do: metadata
  defp put_metadata(metadata, key, value), do: Map.put(metadata, key, value)

  defp plan_opts(opts, target_opts) do
    target_opts
    |> Options.expand_target_opts()
    |> Keyword.put(:ignore, Options.ignored_resources(opts))
    |> put_package_lock(opts)
  end

  defp put_package_lock(plan_opts, opts) do
    plan_opts
    |> put_present(:package_lock, Keyword.get(opts, :package_lock))
    |> put_present(:package_lock_write, Keyword.get(opts, :write_package_lock))
    |> Options.put_repology_cache(opts)
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)
end
