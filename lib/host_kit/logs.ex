defmodule HostKit.Logs do
  @moduledoc "Helpers for extracting log management declarations from HostKit projects."

  alias HostKit.Logs.Config
  alias HostKit.{Project, Runner, Target}

  @spec config(keyword() | boolean()) :: map() | boolean()
  def config(value), do: HostKit.Observability.config(value)

  @spec read(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def read(unit, opts \\ []) when is_binary(unit) do
    unit
    |> journalctl_args(opts)
    |> run_journalctl(opts)
    |> parse_journalctl_output()
  end

  @spec tail(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def tail(unit, opts \\ []) when is_binary(unit) do
    lines = opts |> Keyword.get(:lines, 100) |> to_string()
    read(unit, Keyword.put(opts, :lines, lines))
  end

  @spec configs(Project.t()) :: [Config.t()]
  def configs(%Project{} = project) do
    project_defaults = logs_config(project.meta, %{})

    project.services
    |> Enum.flat_map(&service_configs(&1, project_defaults))
  end

  defp journalctl_args(unit, opts) do
    ["-u", unit, "-o", "json", "--no-pager"]
    |> maybe_append("--since", Keyword.get(opts, :since))
    |> maybe_append("--until", Keyword.get(opts, :until))
    |> maybe_append("-n", Keyword.get(opts, :lines))
  end

  defp maybe_append(args, _flag, nil), do: args
  defp maybe_append(args, flag, value), do: args ++ [flag, to_string(value)]

  defp run_journalctl(args, opts) do
    target = Keyword.get(opts, :target, Target.local(:local))
    runner = Keyword.get(opts, :runner, target.runner)

    runner_opts =
      target
      |> Target.opts(Keyword.get(opts, :runner_opts, []))
      |> Keyword.delete(:runner)

    Runner.cmd(runner, "journalctl", args, runner_opts)
  end

  defp parse_journalctl_output({output, 0}) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, []}, &decode_journal_line/2)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_journalctl_output({output, status}),
    do: {:error, {:journalctl_failed, status, output}}

  defp decode_journal_line(line, {:ok, entries}) do
    case Jason.decode(line) do
      {:ok, entry} -> {:cont, {:ok, [entry | entries]}}
      {:error, error} -> {:halt, {:error, {:invalid_journal_json, line, error}}}
    end
  end

  defp service_configs(service, project_defaults) do
    service_defaults = merge_config(project_defaults, logs_config(service.meta, %{}))
    Enum.flat_map(service.resources, &resource_configs(&1, service_defaults))
  end

  defp resource_configs(resource, service_defaults) do
    case logs_config(resource.meta, :inherit) do
      :inherit ->
        inherited_config(service_defaults, resource)

      resource_config ->
        [config_struct(merge_config(service_defaults, resource_config), resource)]
    end
  end

  defp inherited_config(%{enabled: false}, _resource), do: []
  defp inherited_config(%{} = config, _resource) when map_size(config) == 0, do: []
  defp inherited_config(%{} = config, resource), do: [config_struct(config, resource)]

  defp logs_config(meta, default) do
    meta
    |> Map.get(:observability, %{})
    |> Map.get(:logs, Map.get(meta, :logs, default))
  end

  defp config_struct(config, resource) do
    config
    |> normalize_config()
    |> Map.put(:resource_id, HostKit.Resource.id(resource))
    |> Config.new()
  end

  defp normalize_config(false), do: %{enabled: false}
  defp normalize_config(true), do: %{driver: :journald, ship: true}
  defp normalize_config(config) when is_list(config), do: config(config)
  defp normalize_config(config) when is_map(config), do: config

  defp merge_config(base, override),
    do: HostKit.Observability.merge(base, override, &normalize_config/1)
end
