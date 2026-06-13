defmodule HostKit.Readiness do
  @moduledoc "Readiness check execution for HostKit resources."

  alias HostKit.Readiness.{HTTP, Systemd}
  alias HostKit.Resources.Readiness
  alias HostKit.Runner.Ops

  @spec current?(Readiness.t(), keyword()) :: boolean()
  def current?(%Readiness{} = readiness, opts) do
    readiness.checks
    |> Enum.all?(&(check(&1, opts) == :ok))
  end

  @spec wait(Readiness.t(), keyword()) :: :ok | {:error, term()}
  def wait(%Readiness{} = readiness, opts) do
    with :ok <- prepare(readiness, opts) do
      deadline = System.monotonic_time(:millisecond) + readiness.timeout
      wait_until(readiness, opts, deadline, [])
    end
  end

  defp prepare(%Readiness{checks: checks}, opts) do
    checks
    |> Enum.reduce_while(:ok, fn
      %Systemd{restart: true, unit: unit}, :ok ->
        Ops.cmd(opts, "systemctl", ["reset-failed", unit])

        case Ops.cmd(opts, "systemctl", ["restart", unit]) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      _check, :ok ->
        {:cont, :ok}
    end)
  end

  defp wait_until(readiness, opts, deadline, _last_errors) do
    case check_all(readiness, opts) do
      :ok ->
        :ok

      {:error, errors} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, {:readiness_timeout, readiness.name, errors}}
        else
          Process.sleep(readiness.interval)
          wait_until(readiness, opts, deadline, errors)
        end
    end
  end

  defp check_all(%Readiness{checks: checks}, opts) do
    errors =
      checks
      |> Enum.map(&{&1, check(&1, opts)})
      |> Enum.reject(fn {_check, result} -> result == :ok end)

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp check(%Systemd{unit: unit, state: :active}, opts) do
    Ops.cmd(opts, "systemctl", ["is-active", unit])
  end

  defp check(%HTTP{} = http, opts) do
    format = "%{http_code}"

    case Ops.cmd(opts, "curl", [
           "-fsS",
           "-w",
           format,
           "-o",
           "/tmp/hostkit-readiness-body",
           http.url
         ]) do
      :ok -> check_http_body(http, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_http_body(%HTTP{expect_body: nil}, _opts), do: :ok

  defp check_http_body(%HTTP{expect_body: body}, opts) do
    script = "grep -F #{HostKit.Shell.escape(body)} /tmp/hostkit-readiness-body >/dev/null"

    Ops.cmd(opts, "sh", ["-c", script])
  end
end
