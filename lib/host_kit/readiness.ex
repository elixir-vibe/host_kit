defmodule HostKit.Readiness do
  @moduledoc "Readiness check execution for HostKit resources."

  alias HostKit.Readiness.{HTTP, Systemd}
  alias HostKit.Resources.Readiness
  alias HostKit.Runner.Ops

  @spec current?(Readiness.t(), keyword()) :: boolean()
  def current?(%Readiness{} = readiness, opts) do
    check_all(readiness, opts) == :ok
  end

  @spec wait(Readiness.t(), keyword()) :: :ok | {:error, term()}
  def wait(%Readiness{} = readiness, opts) do
    with :ok <- prepare(readiness, opts) do
      deadline = System.monotonic_time(:millisecond) + readiness.timeout
      wait_until(readiness, opts, deadline, [])
    end
  end

  defp prepare(%Readiness{checks: checks}, opts) do
    units = Enum.filter(checks, &match?(%Systemd{restart: true}, &1))

    case units do
      [] -> :ok
      units -> Ops.cmd(opts, "sh", ["-c", restart_script(units)])
    end
  end

  defp wait_until(readiness, opts, deadline, last_summary) do
    case check_all(readiness, opts) do
      :ok ->
        :ok

      {:error, errors} ->
        summary = summarize_errors(errors)
        maybe_emit_waiting(readiness, summary, last_summary)

        if System.monotonic_time(:millisecond) >= deadline do
          emit(:timeout, readiness, %{summary: summary, errors: errors})
          {:error, {:readiness_timeout, readiness.name, errors}}
        else
          Process.sleep(effective_interval(readiness, opts))
          wait_until(readiness, opts, deadline, summary)
        end
    end
  end

  defp check_all(%Readiness{checks: []}, _opts), do: :ok

  defp check_all(%Readiness{} = readiness, opts) do
    case Ops.cmd(opts, "sh", ["-c", check_script(readiness)]) do
      :ok -> :ok
      {:error, reason} -> {:error, [{readiness, {:error, reason}}]}
    end
  end

  defp restart_script(units) do
    Enum.map_join(units, "\n", fn %Systemd{unit: unit, kill: kill} ->
      escaped = HostKit.Shell.escape(unit)
      kill_script = if kill, do: "systemctl kill --kill-who=all #{escaped} || true\n", else: ""
      "#{kill_script}systemctl reset-failed #{escaped} || true\nsystemctl restart #{escaped}"
    end)
  end

  defp check_script(%Readiness{checks: checks}) do
    [
      "set +e",
      "hostkit_readiness_failed=0",
      Enum.map_join(checks, "\n", &check_script/1),
      "exit $hostkit_readiness_failed"
    ]
    |> Enum.join("\n")
  end

  defp check_script(%Systemd{unit: unit, state: :active}) do
    escaped = HostKit.Shell.escape(unit)

    """
    if ! systemctl is-active --quiet #{escaped}; then
      echo #{HostKit.Shell.escape("systemd #{unit} is not active")}
      hostkit_readiness_failed=1
    fi
    """
  end

  defp check_script(%HTTP{} = http) do
    body_check = http_body_check_script(http)

    """
    hostkit_readiness_body=$(mktemp /tmp/hostkit-readiness-body.XXXXXX)
    hostkit_readiness_status=$(curl -sS -w '%{http_code}' -o "$hostkit_readiness_body" #{HostKit.Shell.escape(http.url)})
    hostkit_readiness_curl_status=$?

    if [ "$hostkit_readiness_curl_status" -ne 0 ]; then
      echo #{HostKit.Shell.escape("http #{http.url} curl failed")} status="$hostkit_readiness_status" exit="$hostkit_readiness_curl_status"
      hostkit_readiness_failed=1
    elif [ "$hostkit_readiness_status" != #{HostKit.Shell.escape(to_string(http.expect_status))} ]; then
      echo #{HostKit.Shell.escape("http #{http.url} unexpected status")} expected=#{HostKit.Shell.escape(to_string(http.expect_status))} actual="$hostkit_readiness_status"
      hostkit_readiness_failed=1
    else
    #{indent(body_check, 2)}
    fi

    rm -f "$hostkit_readiness_body"
    """
  end

  defp http_body_check_script(%HTTP{expect_body: nil}), do: ":"

  defp http_body_check_script(%HTTP{url: url, expect_body: body}) do
    """
    if ! grep -F #{HostKit.Shell.escape(body)} "$hostkit_readiness_body" >/dev/null; then
      echo #{HostKit.Shell.escape("http #{url} body did not contain expected text")}
      hostkit_readiness_failed=1
    fi
    """
  end

  defp effective_interval(%Readiness{interval: 500}, opts) do
    if remote_runner?(Keyword.get(opts, :runner, HostKit.Runner.Local)), do: 1_000, else: 500
  end

  defp effective_interval(%Readiness{interval: interval}, _opts), do: interval

  defp maybe_emit_waiting(readiness, summary, previous) do
    if summary != previous do
      emit(:waiting, readiness, %{summary: summary})
    end
  end

  defp emit(type, readiness, metadata) do
    HostKit.Telemetry.execute(
      [:readiness, type],
      %{system_time: System.system_time()},
      Map.merge(%{name: readiness.name}, metadata)
    )
  end

  defp summarize_errors(errors) do
    errors
    |> Enum.map_join(", ", fn {_check, {:error, reason}} ->
      HostKit.Error.format(reason, max: 240)
    end)
    |> String.replace("\n", " ")
  end

  defp remote_runner?(HostKit.Runner.SSH), do: true
  defp remote_runner?({HostKit.Runner.SSH, _opts}), do: true
  defp remote_runner?({HostKit.Runner.SSH.Connection, _opts}), do: true
  defp remote_runner?(_runner), do: false

  defp indent(text, spaces) do
    prefix = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", &(prefix <> &1))
  end
end
