defmodule Mix.Tasks.HostKit.Audit do
  @moduledoc """
  Audits a HostKit config against the selected target.

      mix host_kit.audit [options] [config.exs]

  The audit output starts with a compact host report and then prints the normal
  plan diff. Use `--format json` for machine-readable output.
  """

  use Mix.Task

  alias Mix.Tasks.HostKit.Options

  @shortdoc "Audit declared HostKit resources"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional} = parse!(args)
    path = List.first(positional) || "infra/config.exs"
    project = HostKit.load!(path, require: Keyword.get_values(opts, :require))

    Options.with_target_opts(opts, project, fn target_opts ->
      case HostKit.Project.audit(project, audit_opts(opts, target_opts)) do
        {:ok, plan} -> IO.puts(format_audit(plan, opts))
        {:error, reason} -> Mix.raise("HostKit audit failed: #{inspect(reason)}")
      end
    end)
  end

  defp parse!(args) do
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
        ignore: :keep,
        package_lock: :string,
        repology_cache: :string,
        repology_cache_ttl: :integer,
        repology_no_cache: :boolean
      ]
    )
  end

  defp audit_opts(opts, target_opts) do
    target_opts
    |> Options.expand_target_opts()
    |> Keyword.put(:ignore, Options.ignored_resources(opts))
    |> put_present(:package_lock, Keyword.get(opts, :package_lock))
    |> Options.put_repology_cache(opts)
  end

  defp format_audit(plan, opts) do
    report = HostKit.Plan.Summary.audit_report(plan)

    case Keyword.get(opts, :format, "text") do
      "json" ->
        %{
          report: report,
          plan: plan |> HostKit.Plan.Artifact.from_plan() |> HostKit.Plan.Artifact.dump()
        }
        |> Jason.encode_to_iodata!(pretty: true)

      "inspect" ->
        inspect(%{report: report, plan: plan}, pretty: true, limit: :infinity, structs: true)

      "text" ->
        [format_report(report), "\n\n", HostKit.Plan.Format.format(plan)]
        |> IO.iodata_to_binary()

      format ->
        Mix.raise("unknown --format #{inspect(format)}, expected text, inspect, or json")
    end
  end

  defp format_report(report) do
    [
      "Audit: ",
      to_string(report.managed_resources),
      " managed resources, ",
      to_string(report.drift),
      " drift, ",
      to_string(report.read_errors),
      " read errors, ",
      to_string(report.redacted_config_entries),
      " redacted config entries, ",
      to_string(report.unchanged),
      " unchanged",
      "\nResources: ",
      Mix.Tasks.HostKit.Output.format_counts(report.resources_by_type),
      "\nDrift: ",
      Mix.Tasks.HostKit.Output.format_counts(report.drift_by_type),
      format_redacted_config(report.redacted_config_paths)
    ]
  end

  defp format_redacted_config([]), do: []

  defp format_redacted_config(entries) do
    [
      "\nRedacted config: ",
      Enum.map_join(entries, "; ", fn entry ->
        "#{format_resource_id(HostKit.Resource.load(entry.resource_id))}: #{Enum.join(entry.paths, ", ")}"
      end)
    ]
  end

  defp format_resource_id({type, name}), do: "#{type}.#{name}"
  defp format_resource_id(resource_id), do: inspect(resource_id)

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)
end
