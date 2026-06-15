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
    report = audit_report(plan)

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

  defp audit_report(plan) do
    counts = Enum.frequencies_by(plan.changes, & &1.action)

    %{
      managed_resources: length(plan.resources),
      drift:
        Map.get(counts, :create, 0) + Map.get(counts, :update, 0) + Map.get(counts, :delete, 0),
      read_errors: Map.get(counts, :read, 0),
      unchanged: Map.get(counts, :no_op, 0),
      redacted_keys: redacted_key_count(plan.resources)
    }
  end

  defp redacted_key_count(resources) do
    resources
    |> Enum.flat_map(fn
      %HostKit.Resources.ConfigFile{} = config ->
        HostKit.Resources.ConfigFile.secret_paths(config)

      _resource ->
        []
    end)
    |> length()
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
      to_string(report.redacted_keys),
      " redacted keys, ",
      to_string(report.unchanged),
      " unchanged"
    ]
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)
end
