defmodule HostKit.SystemdRuntime do
  @moduledoc "Systemd runtime operations for HostKit apply and readiness."

  alias HostKit.Readiness.Systemd, as: SystemdCheck
  alias HostKit.Runner.Ops

  @spec reload(keyword()) :: :ok | {:error, term()}
  def reload(opts \\ []) do
    if native_mutation?(opts) do
      Systemd.reload(systemd_opts(opts))
    else
      Ops.cmd(opts, "systemctl", ["daemon-reload"])
    end
  end

  @spec restart(SystemdCheck.t() | String.t(), keyword()) :: :ok | {:error, term()}
  def restart(%SystemdCheck{unit: unit, kill: kill}, opts) do
    restart(unit, Keyword.put(opts, :kill, kill))
  end

  def restart(unit, opts) when is_binary(unit) do
    if native_mutation?(opts) do
      restart_native(unit, opts)
    else
      restart_runner(unit, opts)
    end
  end

  @spec active?(String.t(), keyword()) :: :ok | {:error, term()}
  def active?(unit, opts) when is_binary(unit) do
    if local_runner?(opts) do
      case Systemd.unit_state(unit, systemd_opts(opts)) do
        {:ok, %{active_state: "active"}} -> :ok
        {:ok, state} -> {:error, {:systemd_not_active, unit, state}}
        {:error, reason} -> {:error, reason}
      end
    else
      Ops.cmd(opts, "systemctl", ["is-active", "--quiet", unit])
    end
  end

  defp restart_native(unit, opts) do
    if Keyword.get(opts, :kill, false) do
      _ = Systemd.kill_unit(unit, "all", 15, systemd_opts(opts))
    end

    _ = Systemd.reset_failed_unit(unit, systemd_opts(opts))

    unit
    |> Systemd.restart_unit(systemd_opts(opts))
    |> normalize_job_result()
  end

  defp restart_runner(unit, opts) do
    if Keyword.get(opts, :kill, false) do
      _ = Ops.cmd(opts, "systemctl", ["kill", "--kill-who=all", unit])
    end

    _ = Ops.cmd(opts, "systemctl", ["reset-failed", unit])
    Ops.cmd(opts, "systemctl", ["restart", unit])
  end

  defp normalize_job_result(:ok), do: :ok
  defp normalize_job_result({:ok, _job}), do: :ok
  defp normalize_job_result({:error, _reason} = error), do: error

  defp native_mutation?(opts), do: local_runner?(opts) and not Keyword.get(opts, :sudo, false)

  defp local_runner?(opts) do
    case Keyword.get(opts, :runner, HostKit.Runner.Local) do
      HostKit.Runner.Local -> true
      {HostKit.Runner.Local, _runner_opts} -> true
      _other -> false
    end
  end

  defp systemd_opts(opts) do
    opts
    |> Keyword.take([:bus, :mode, :wait, :timeout, :interval])
    |> Keyword.put_new(:bus, :system)
  end
end
