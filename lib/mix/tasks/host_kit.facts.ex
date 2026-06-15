defmodule Mix.Tasks.HostKit.Facts do
  @moduledoc """
  Collects bounded host facts through a HostKit target.

      mix host_kit.facts [options] [config.exs]

  Examples:

      mix host_kit.facts --local --only os,users
      mix host_kit.facts --host prod infra/config.exs --only os,systemd,ports
  """

  use Mix.Task

  alias Mix.Tasks.HostKit.Options

  @shortdoc "Collect host facts"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional} = parse!(args)
    project = maybe_load_project(positional, opts)

    Options.with_target_opts(opts, project, fn target_opts ->
      facts_opts = target_opts |> Options.expand_target_opts() |> Keyword.put(:only, only(opts))

      {:ok, facts} = HostKit.Facts.collect(facts_opts)
      IO.puts(format_facts(facts, opts))
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
        only: :string
      ]
    )
  end

  defp maybe_load_project(positional, opts) do
    cond do
      path = List.first(positional) ->
        HostKit.load!(path, require: Keyword.get_values(opts, :require))

      Keyword.has_key?(opts, :host) ->
        HostKit.load!("infra/config.exs", require: Keyword.get_values(opts, :require))

      true ->
        nil
    end
  end

  defp only(opts) do
    opts
    |> Keyword.get(:only, "os,users,systemd,ports")
    |> String.split(",", trim: true)
    |> Enum.map(fn name -> name |> String.trim() |> String.to_existing_atom() end)
  rescue
    ArgumentError ->
      Mix.raise("invalid --only value, expected comma-separated os,users,systemd,ports")
  end

  defp format_facts(facts, opts) do
    case Keyword.get(opts, :format, "text") do
      "json" ->
        Jason.encode_to_iodata!(facts, pretty: true)

      "inspect" ->
        inspect(facts, pretty: true, limit: :infinity, structs: true)

      "text" ->
        facts
        |> Enum.map(&format_fact/1)
        |> Enum.intersperse("\n")
        |> IO.iodata_to_binary()

      format ->
        Mix.raise("unknown --format #{inspect(format)}, expected text, inspect, or json")
    end
  end

  defp format_fact({:os, %{os_release: os_release, kernel: kernel}}) do
    name = Map.get(os_release, "PRETTY_NAME") || Map.get(os_release, "NAME") || "unknown"
    ["os: ", name, " (", kernel || "unknown kernel", ")"]
  end

  defp format_fact({:users, users}) do
    ["users: ", Enum.map_join(users, ", ", & &1.name)]
  end

  defp format_fact({:systemd, systemd}) do
    [
      "systemd: ",
      systemd.version || "unknown",
      ", failed_units=",
      systemd.failed_units |> length() |> to_string()
    ]
  end

  defp format_fact({:ports, ports}) do
    rendered = Enum.map_join(ports, ", ", fn port -> "#{port.address}:#{port.port}" end)

    ["ports: ", rendered]
  end
end
