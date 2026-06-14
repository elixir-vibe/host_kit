defmodule Mix.Tasks.HostKit.Instance do
  @moduledoc """
  Manages lifecycle for a declared HostKit instance.

  This task is backend-neutral at the CLI boundary: it loads an `instance`
  declaration, then delegates to the instance's declared backend.
  Backend-specific operational knobs stay in backend configuration or environment.
  """

  use Mix.Task

  @shortdoc "Manage a declared HostKit instance"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional} =
      OptionParser.parse!(args,
        strict: [
          require: :keep
        ]
      )

    case positional do
      [command, name | rest] when command in ["status", "ensure", "destroy"] ->
        path = List.first(rest) || "infra/config.exs"
        project = HostKit.load!(path, require: Keyword.get_values(opts, :require))
        instance = fetch_instance!(project, name)
        run_command(command, instance)

      _other ->
        Mix.raise("expected: mix host_kit.instance status|ensure|destroy INSTANCE [config.exs]")
    end
  end

  defp fetch_instance!(project, name) do
    case HostKit.Project.fetch_instance(project, name) do
      {:ok, instance} -> instance
      :error -> Mix.raise("instance #{inspect(name)} is not declared in #{inspect(project.name)}")
    end
  end

  defp run_command("status", instance) do
    case HostKit.Instance.Backend.read(instance, []) do
      {:ok, %HostKit.Instance{} = actual} ->
        IO.puts("present #{format_instance(actual)}")

      {:ok, nil} ->
        IO.puts("absent #{format_instance(instance)}")

      {:error, reason} ->
        Mix.raise("could not read instance #{instance.name}: #{inspect(reason)}")
    end
  end

  defp run_command("ensure", instance) do
    case HostKit.Instance.Backend.apply(instance, []) do
      :ok ->
        IO.puts("ensured #{format_instance(instance)}")

      {:error, reason} ->
        Mix.raise("could not ensure instance #{instance.name}: #{inspect(reason)}")
    end
  end

  defp run_command("destroy", instance) do
    case HostKit.Instance.Backend.delete(instance, []) do
      :ok ->
        IO.puts("destroyed #{format_instance(instance)}")

      {:error, reason} ->
        Mix.raise("could not destroy instance #{instance.name}: #{inspect(reason)}")
    end
  end

  defp format_instance(%HostKit.Instance{} = instance) do
    "#{instance.name} backend=#{instance.backend || "none"} lifecycle=#{instance.lifecycle}"
  end
end
