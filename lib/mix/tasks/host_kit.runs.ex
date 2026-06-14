defmodule Mix.Tasks.HostKit.Runs do
  @moduledoc """
  Lists minimal HostKit run records.
  """

  use Mix.Task

  alias Mix.Tasks.HostKit.Options

  @shortdoc "List tracked HostKit runs"

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
          runs_root: :string,
          format: :string,
          verbose: :boolean
        ]
      )

    project = load_project(opts, positional)

    Options.with_target_opts(opts, project, fn target_opts ->
      case HostKit.RunRecord.list(run_opts(opts, target_opts)) do
        {:ok, records} -> IO.puts(format_records(records, opts))
        {:error, reason} -> Mix.raise("could not list HostKit runs: #{inspect(reason)}")
      end
    end)
  end

  defp load_project(opts, positional) do
    if Keyword.has_key?(opts, :host) do
      path = List.first(positional) || "infra/config.exs"
      HostKit.load!(path, require: Keyword.get_values(opts, :require))
    end
  end

  defp run_opts(opts, target_opts) do
    target_opts
    |> expand_target_opts()
    |> put_present(:hostkit_runs_root, Keyword.get(opts, :runs_root))
  end

  defp expand_target_opts(opts) do
    case Keyword.pop(opts, :target) do
      {%HostKit.Target{} = target, opts} -> HostKit.Target.opts(target, opts)
      {nil, opts} -> opts
    end
  end

  defp format_records(records, opts) do
    case Keyword.get(opts, :format, "text") do
      "json" -> records |> Enum.map(&JSONCodec.dump/1) |> Jason.encode!(pretty: true)
      "inspect" -> inspect(records, pretty: true, limit: :infinity)
      "text" -> Enum.map_join(records, "\n", &format_record(&1, opts))
    end
  end

  defp format_record(record, opts) do
    summary =
      [
        record.id,
        record.direction,
        record.project,
        record.applied_at,
        "changes=#{length(record.changes)}",
        "artifacts=#{map_size(record.artifacts || %{})}",
        "backups=#{map_size(record.backups || %{})}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    if Keyword.get(opts, :verbose, false) do
      [
        summary,
        format_paths("artifacts", record.artifacts),
        format_paths("backups", record.backups)
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
    else
      summary
    end
  end

  defp format_paths(_label, nil), do: ""
  defp format_paths(_label, map) when map_size(map) == 0, do: ""

  defp format_paths(label, map) do
    lines =
      map
      |> Enum.sort_by(fn {key, _path} -> key end)
      |> Enum.map(fn {key, path} -> "  #{label}.#{key}=#{path}" end)

    Enum.join(lines, "\n")
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)
end
