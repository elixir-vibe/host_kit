defmodule Mix.Tasks.HostKit.Down do
  @moduledoc """
  Builds a down/rollback plan from an existing HostKit plan artifact.

  Rollback is just another plan: inspect the generated down plan, save it if you
  want, then apply it with `mix host_kit.apply --plan down.plan.json --confirm`.
  """

  use Mix.Task

  alias Mix.Tasks.HostKit.Options

  @shortdoc "Build a HostKit down plan"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional} =
      OptionParser.parse!(args,
        strict: [
          plan: :string,
          out: :string,
          format: :string,
          only: :keep,
          except: :keep,
          last: :boolean,
          run: :string,
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
          runs_root: :string
        ]
      )

    project = load_project(opts, positional)

    Options.with_target_opts(opts, project, fn target_opts ->
      plan = load_up_plan!(opts, positional, target_opts)

      {:ok, down_plan} = HostKit.down(plan, down_opts(opts))
      maybe_write_artifact(down_plan, opts)
      IO.puts(Mix.Tasks.HostKit.Output.format_plan(down_plan, opts))
    end)
  end

  defp load_project(opts, positional) do
    if Keyword.has_key?(opts, :host) do
      path = List.first(positional) || "infra/config.exs"
      HostKit.load!(path, require: Keyword.get_values(opts, :require))
    end
  end

  defp load_up_plan!(opts, positional, target_opts) do
    cond do
      Keyword.get(opts, :last, false) ->
        {path, record} = tracked_plan_artifact!(:latest, opts, target_opts)
        path |> load_plan_artifact!(target_opts) |> HostKit.RunRecord.apply_backups(record)

      run_id = Keyword.get(opts, :run) ->
        {path, record} = tracked_plan_artifact!(run_id, opts, target_opts)
        path |> load_plan_artifact!(target_opts) |> HostKit.RunRecord.apply_backups(record)

      true ->
        path =
          Keyword.get(opts, :plan) || List.first(positional) ||
            Mix.raise("expected a plan artifact")

        load_plan_artifact!(path, target_opts)
    end
  end

  defp load_plan_artifact!(path, target_opts) do
    case HostKit.Plan.Artifact.load(path, expand_target_opts(target_opts)) do
      {:ok, plan} -> plan
      {:error, reason} -> Mix.raise("could not load HostKit plan artifact: #{inspect(reason)}")
    end
  end

  defp tracked_plan_artifact!(selector, opts, target_opts) do
    run_opts =
      target_opts
      |> expand_target_opts()
      |> put_present(:hostkit_runs_root, Keyword.get(opts, :runs_root))

    case load_run_record(selector, run_opts) do
      {:ok, %{artifacts: %{"up_plan" => path}} = record} when is_binary(path) ->
        {path, record}

      {:ok, record} ->
        Mix.raise("HostKit run #{inspect(record.id)} does not reference an up plan artifact")

      {:error, reason} ->
        Mix.raise("could not load HostKit run: #{inspect(reason)}")
    end
  end

  defp load_run_record(:latest, run_opts), do: HostKit.RunRecord.latest(run_opts)
  defp load_run_record(id, run_opts), do: HostKit.RunRecord.load(id, run_opts)

  defp down_opts(opts) do
    []
    |> put_filter(:only, Keyword.get_values(opts, :only))
    |> put_filter(:except, Keyword.get_values(opts, :except))
  end

  defp expand_target_opts(opts) do
    case Keyword.pop(opts, :target) do
      {%HostKit.Target{} = target, opts} -> HostKit.Target.opts(target, opts)
      {nil, opts} -> opts
    end
  end

  defp put_filter(opts, _key, []), do: opts

  defp put_filter(opts, key, values),
    do: Keyword.put(opts, key, Enum.map(values, &parse_resource_id/1))

  defp parse_resource_id(resource) do
    case String.split(resource, ":", parts: 2) do
      [type, name] -> {resource_type(type), name}
      _ -> Mix.raise("invalid resource id #{inspect(resource)}, expected type:name")
    end
  end

  defp resource_type(type) do
    String.to_existing_atom(type)
  rescue
    ArgumentError -> Mix.raise("unknown resource type: #{inspect(type)}")
  end

  defp maybe_write_artifact(plan, opts) do
    case Keyword.get(opts, :out) do
      nil ->
        :ok

      path ->
        case HostKit.Plan.Artifact.save(path, plan) do
          :ok ->
            :ok

          {:error, reason} ->
            Mix.raise("could not write HostKit down plan artifact: #{inspect(reason)}")
        end
    end
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)
end
