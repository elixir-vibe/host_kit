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
        plan.changes
        |> Enum.map(fn change ->
          %{
            resource_id: HostKit.Resource.dump(change.resource_id),
            action: change.action,
            before: HostKit.Resource.dump(change.before)
          }
        end)
        |> Jason.encode_to_iodata!(pretty: true)

      "inspect" ->
        plan.changes
        |> Enum.map(& &1.before)
        |> inspect(pretty: true, limit: :infinity, structs: true)

      "text" ->
        Enum.map_join(plan.changes, "\n", &format_read_change/1)

      format ->
        Mix.raise("unknown --format #{inspect(format)}, expected text, inspect, or json")
    end
  end

  defp format_read_change(change) do
    status = if is_nil(change.before), do: "missing", else: "present"
    "#{format_resource_id(change.resource_id)} #{status}"
  end

  defp format_resource_id({type, name}), do: "#{type}.#{name}"
  defp format_resource_id(resource_id), do: inspect(resource_id)
end
