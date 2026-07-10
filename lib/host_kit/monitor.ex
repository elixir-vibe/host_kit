defmodule HostKit.Monitor do
  @moduledoc "Helpers for extracting monitoring declarations from HostKit projects."

  alias HostKit.Monitor.{Check, Endpoint, Result}
  alias HostKit.{Project, Runner, Target}

  @spec check(atom(), keyword()) :: Check.t()
  def check(type, opts) when is_atom(type) do
    opts
    |> Keyword.put(:type, type)
    |> Keyword.put_new(:target, Keyword.get(opts, :url, Keyword.get(opts, :unit)))
    |> Check.new()
  end

  @spec checks(Project.t()) :: [Check.t()]
  def checks(%Project{} = project) do
    project
    |> Project.resources()
    |> Enum.flat_map(&resource_checks/1)
  end

  @spec endpoint_checks(Project.t() | [Check.t()], keyword()) :: [Endpoint.t()]
  def endpoint_checks(project_or_checks, opts \\ [])

  def endpoint_checks(%Project{} = project, opts) do
    project
    |> checks()
    |> endpoint_checks(opts)
  end

  def endpoint_checks(checks, opts) when is_list(checks) do
    Enum.flat_map(checks, &endpoint_check(&1, opts))
  end

  @spec run(Project.t(), keyword()) :: {:ok, [Result.t()]} | {:error, term()}
  def run(%Project{} = project, opts \\ []) do
    project
    |> checks()
    |> Enum.map(&run_check(&1, opts))
    |> then(&{:ok, &1})
  end

  defp resource_checks(resource) do
    resource
    |> Map.get(:meta, %{})
    |> Map.get(:monitor, [])
    |> List.wrap()
  end

  defp endpoint_check(%Check{type: :http, target: url} = check, opts) when is_binary(url) do
    [
      %Endpoint{
        name: check.name,
        group: check.group || Keyword.get(opts, :group),
        url: url,
        interval: check.interval || Keyword.get(opts, :interval),
        expect: check.expect,
        alerts: default_list(check.alerts, Keyword.get(opts, :alerts, [])),
        severity: check.severity,
        source: check
      }
    ]
  end

  defp endpoint_check(%Check{}, _opts), do: []

  defp default_list([], default), do: default
  defp default_list(nil, default), do: default
  defp default_list(value, _default), do: value

  defp run_check(%Check{type: :systemd} = check, opts) do
    unit = check.target || unit_from_resource_id(check.resource_id)
    target = Keyword.get(opts, :target, Target.local(:local))
    runner = Keyword.get(opts, :runner, target.runner)

    runner_opts =
      target |> Target.opts(Keyword.get(opts, :runner_opts, [])) |> Keyword.delete(:runner)

    case Runner.cmd(
           runner,
           "systemctl",
           ["is-active", unit],
           Keyword.put(runner_opts, :stderr_to_stdout, true)
         ) do
      {output, 0} when output in ["active", "active\n"] ->
        Result.ok(check, %{state: :active, unit: unit})

      {output, status} ->
        Result.error(check, {:unexpected_state, String.trim(output)}, %{
          status: status,
          unit: unit
        })
    end
  end

  defp run_check(%Check{type: :http} = check, opts) do
    expected_status = get_in(check.expect, [:status]) || 200

    with {:ok, status} <- http_status(check.target, opts),
         true <- status == expected_status do
      Result.ok(check, %{status: status})
    else
      false -> Result.error(check, {:unexpected_status, expected_status}, %{})
      {:error, reason} -> Result.error(check, reason)
    end
  end

  defp run_check(%Check{type: :command} = check, opts) do
    expected_exit = get_in(check.expect, [:exit]) || 0

    case monitor_exec(check) do
      {:ok, {command, args}} ->
        target = Keyword.get(opts, :target, Target.local(:local))
        runner = Keyword.get(opts, :runner, target.runner)

        runner_opts =
          target |> Target.opts(Keyword.get(opts, :runner_opts, [])) |> Keyword.delete(:runner)

        {command, args} = maybe_sudo(command, args, runner_opts)

        case Runner.cmd(runner, command, args, Keyword.put(runner_opts, :stderr_to_stdout, true)) do
          {output, ^expected_exit} ->
            Result.ok(check, %{exit: expected_exit, output: output})

          {output, status} ->
            Result.error(check, {:unexpected_exit, expected_exit, status}, %{
              exit: status,
              output: output
            })
        end

      {:error, reason} ->
        Result.error(check, reason)
    end
  end

  defp run_check(%Check{type: :filesystem} = check, _opts) do
    path = check.target || path_from_resource_id(check.resource_id)

    if File.exists?(path) do
      Result.ok(check, %{exists: true, path: path})
    else
      Result.error(check, :missing, %{exists: false, path: path})
    end
  end

  defp run_check(%Check{} = check, _opts),
    do: Result.error(check, {:unsupported_check_type, check.type})

  defp unit_from_resource_id({:systemd_service, unit}), do: unit
  defp unit_from_resource_id({:systemd_timer, unit}), do: unit
  defp unit_from_resource_id(_resource_id), do: nil

  defp path_from_resource_id({_type, path}) when is_binary(path), do: path
  defp path_from_resource_id(_resource_id), do: nil

  defp monitor_exec(%Check{exec: nil}), do: {:error, :missing_exec}

  defp monitor_exec(%Check{exec: exec}) do
    {:ok, HostKit.CommandLine.to_exec(exec)}
  rescue
    ArgumentError -> {:error, :invalid_exec}
    FunctionClauseError -> {:error, :invalid_exec}
  end

  defp maybe_sudo(command, args, opts) do
    if Keyword.get(opts, :sudo, false), do: {"sudo", [command | args]}, else: {command, args}
  end

  defp http_status(nil, _opts), do: {:error, :missing_url}

  defp http_status(url, opts) do
    request_opts =
      [
        retry: false,
        receive_timeout: Keyword.get(opts, :http_timeout, 5_000),
        into: &discard_body/2
      ]
      |> Keyword.merge(Keyword.get(opts, :req_options, []))

    case Req.get(url, request_opts) do
      {:ok, %Req.Response{status: status}} -> {:ok, status}
      {:error, reason} -> {:error, reason}
    end
  end

  defp discard_body({:data, _data}, request_and_response),
    do: {:cont, request_and_response}
end
