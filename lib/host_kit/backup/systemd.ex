defmodule HostKit.Backup.Systemd do
  @moduledoc "Small systemd wrapper used by the backup runner."

  @spec active?(String.t(), keyword()) :: boolean()
  def active?(unit, opts \\ []) do
    match?({:ok, _output}, cmd("systemctl", ["is-active", "--quiet", unit], opts))
  end

  @spec stop(String.t(), keyword()) :: :ok | {:error, term()}
  def stop(unit, opts \\ []), do: unit_cmd("stop", unit, opts)

  @spec start(String.t(), keyword()) :: :ok | {:error, term()}
  def start(unit, opts \\ []), do: unit_cmd("start", unit, opts)

  @spec wait_active(String.t(), keyword()) :: :ok | {:error, term()}
  def wait_active(unit, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout, 60_000)
    interval_ms = Keyword.get(opts, :interval, 1_000)
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_active(unit, deadline, interval_ms, opts)
  end

  defp wait_active(unit, deadline, interval_ms, opts) do
    cond do
      active?(unit, opts) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, {:systemd_wait_active_timeout, unit}}

      true ->
        Process.sleep(interval_ms)
        wait_active(unit, deadline, interval_ms, opts)
    end
  end

  defp unit_cmd(action, unit, opts) do
    with {:ok, _output} <- cmd("systemctl", [action, unit], opts), do: :ok
  end

  defp cmd(command, args, opts) do
    runner = Keyword.get(opts, :runner, &System.cmd/3)

    case runner.(command, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, status} -> {:error, {:command_failed, command, args, status, output}}
    end
  end
end
