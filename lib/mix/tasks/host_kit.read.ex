defmodule Mix.Tasks.HostKit.Read do
  @moduledoc """
  Reads current target state for the resources declared by a HostKit config.

      mix host_kit.read [options] [config.exs]

  Use `--local` for local reads or `--host NAME config.exs` for a declared remote host.
  """

  use Mix.Task

  alias Mix.Tasks.HostKit.Options

  @shortdoc "Read current state for declared HostKit resources"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional} = parse!(args)
    path = List.first(positional) || "infra/config.exs"
    project = HostKit.load!(path, require: Keyword.get_values(opts, :require))

    Options.with_target_opts(opts, project, fn target_opts ->
      case HostKit.Project.audit(project, target_opts) do
        {:ok, plan} -> IO.puts(format_read(plan, opts))
        {:error, reason} -> Mix.raise("HostKit read failed: #{inspect(reason)}")
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
        format: :string
      ]
    )
  end

  defp format_read(plan, opts) do
    case Keyword.get(opts, :format, "text") do
      "json" ->
        %{
          report: read_report(plan),
          resources:
            Enum.map(plan.changes, fn change ->
              %{
                resource_id: HostKit.Resource.dump(change.resource_id),
                status: read_status(change),
                action: change.action,
                before: HostKit.Resource.dump(change.before)
              }
            end)
        }
        |> Jason.encode_to_iodata!(pretty: true)

      "inspect" ->
        %{report: read_report(plan), resources: Enum.map(plan.changes, & &1.before)}
        |> inspect(pretty: true, limit: :infinity, structs: true)

      "text" ->
        [format_read_report(plan), "\n", Enum.map_join(plan.changes, "\n", &format_read_change/1)]

      format ->
        Mix.raise("unknown --format #{inspect(format)}, expected text, inspect, or json")
    end
  end

  defp read_report(plan) do
    actions = HostKit.Plan.Summary.action_counts(plan)

    %{
      managed_resources: length(plan.resources),
      resources_by_type: HostKit.Plan.Summary.resource_counts(plan),
      present:
        Map.fetch!(actions, "no_op") + Map.fetch!(actions, "update") +
          Map.fetch!(actions, "delete"),
      missing: Map.fetch!(actions, "create"),
      read_errors: Map.fetch!(actions, "read")
    }
  end

  defp format_read_report(plan) do
    report = read_report(plan)

    [
      "Read: ",
      to_string(report.present),
      " present, ",
      to_string(report.missing),
      " missing, ",
      to_string(report.read_errors),
      " read errors across ",
      to_string(report.managed_resources),
      " managed resources",
      "\nResources: ",
      Mix.Tasks.HostKit.Output.format_counts(report.resources_by_type)
    ]
  end

  defp format_read_change(change) do
    "#{format_resource_id(change.resource_id)} #{read_status(change)}"
  end

  defp read_status(%{action: :read}), do: "read_error"
  defp read_status(%{action: :create}), do: "missing"
  defp read_status(%{before: nil}), do: "missing"
  defp read_status(_change), do: "present"

  defp format_resource_id({type, name}), do: "#{type}.#{name}"
  defp format_resource_id(resource_id), do: inspect(resource_id)
end
