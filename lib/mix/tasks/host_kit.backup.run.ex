defmodule Mix.Tasks.HostKit.Backup.Run do
  @moduledoc "Runs a HostKit backup job from an existing HostKit config."

  use Mix.Task

  @shortdoc "Run a HostKit backup job"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional} =
      OptionParser.parse!(args,
        strict: [require: :keep],
        aliases: []
      )

    case positional do
      [job, config] ->
        project = HostKit.load!(config, require: Keyword.get_values(opts, :require))

        case HostKit.Backup.Runner.run(project, job) do
          {:ok, result} ->
            Mix.shell().info("Backup #{job} complete: #{result.manifest}")

          {:error, reason} ->
            Mix.raise("HostKit backup #{job} failed: #{inspect(reason)}")
        end

      _other ->
        Mix.raise("expected: mix host_kit.backup.run JOB CONFIG")
    end
  end
end
