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
    emit_apply(opts, :readiness_started, readiness)
    emit_check_started(readiness, opts)

    case prepare(readiness, opts) do
      :ok ->
        started_at = System.monotonic_time(:millisecond)
        deadline = started_at + readiness.timeout

        case wait_until(readiness, opts, %{
               deadline: deadline,
               started_at: started_at,
               attempt: 1,
               last_summary: []
             }) do
          :ok ->
            emit_check_passed(readiness, opts)
            emit_apply(opts, :readiness_passed, readiness)
            :ok

          {:error, reason} = error ->
            emit_check_failed(readiness, opts, reason)
            emit_apply(opts, :readiness_failed, readiness, reason: reason)
            error
        end

      {:error, reason} = error ->
        emit_apply(opts, :readiness_failed, readiness, reason: reason)
        error
    end
  end

  defp prepare(%Readiness{checks: checks} = readiness, opts) do
    units = Enum.filter(checks, &match?(%Systemd{restart: true}, &1))

    case units do
      [] ->
        :ok

      units ->
        Enum.each(units, &emit_service_restart(opts, readiness, &1, :service_restart_started))

        case Ops.cmd(opts, "sh", ["-c", restart_script(units)]) do
          :ok ->
            Enum.each(
              units,
              &emit_service_restart(opts, readiness, &1, :service_restart_finished)
            )

            :ok

          {:error, reason} = error ->
            Enum.each(units, &emit_service_restart(opts, readiness, &1, :service_failed, reason))
            error
        end
    end
  end

  defp wait_until(readiness, opts, state) do
    case check_all(readiness, opts) do
      :ok ->
        :ok

      {:error, errors} ->
        summary = summarize_errors(errors)
        now = System.monotonic_time(:millisecond)
        maybe_emit_waiting(readiness, summary, state, opts, now)

        if now >= state.deadline do
          emit(:timeout, readiness, %{summary: summary, errors: errors})
          {:error, {:readiness_timeout, readiness.name, errors}}
        else
          Process.sleep(effective_interval(readiness, opts))

          wait_until(readiness, opts, %{state | attempt: state.attempt + 1, last_summary: summary})
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

  defp maybe_emit_waiting(readiness, summary, state, opts, now) do
    if emit_waiting?(summary, state, now) do
      details = %{
        summary: summary,
        attempt: state.attempt,
        elapsed_ms: now - state.started_at,
        timeout_ms: readiness.timeout
      }

      emit(:waiting, readiness, Map.put(details, :summary, summary))
      emit_apply(opts, :readiness_waiting, readiness, details: details)
      emit_http_waiting(readiness, opts, details)
    end
  end

  defp emit_waiting?(summary, state, now) do
    summary != state.last_summary or rem(state.attempt, 10) == 0 or now >= state.deadline
  end

  defp emit(type, readiness, metadata) do
    HostKit.Telemetry.execute(
      [:readiness, type],
      %{system_time: System.system_time()},
      Map.merge(%{name: readiness.name}, metadata)
    )
  end

  defp emit_check_started(%Readiness{checks: checks} = readiness, opts) do
    Enum.each(checks, fn
      %Systemd{} ->
        :ok

      %HTTP{} = http ->
        emit_apply(opts, :health_check_started, readiness, details: %{url: http.url})
    end)
  end

  defp emit_check_passed(%Readiness{checks: checks} = readiness, opts) do
    Enum.each(checks, fn
      %Systemd{} = systemd ->
        emit_service_restart(opts, readiness, systemd, :service_active)

      %HTTP{} = http ->
        emit_apply(opts, :health_check_passed, readiness, details: %{url: http.url})
    end)
  end

  defp emit_check_failed(%Readiness{checks: checks} = readiness, opts, reason) do
    Enum.each(checks, fn
      %Systemd{} = systemd ->
        emit_service_restart(opts, readiness, systemd, :service_failed, reason)

      %HTTP{} = http ->
        emit_apply(opts, :health_check_failed, readiness,
          reason: reason,
          details: %{url: http.url}
        )
    end)
  end

  defp emit_http_waiting(%Readiness{checks: checks} = readiness, opts, details) do
    Enum.each(checks, fn
      %HTTP{} = http ->
        emit_apply(opts, :health_check_waiting, readiness,
          details: Map.merge(details, %{url: http.url})
        )

      _check ->
        :ok
    end)
  end

  defp emit_service_restart(opts, readiness, %Systemd{unit: unit}, type, reason \\ nil) do
    emit_apply(opts, type, readiness, reason: reason, details: %{unit: unit})
  end

  defp emit_apply(opts, type, readiness, attrs \\ []) do
    attrs =
      attrs
      |> Keyword.put_new(:resource_id, HostKit.Resources.Readiness.id(readiness))
      |> Keyword.put_new(:details, %{})

    HostKit.Apply.Events.emit(opts, type, attrs)
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
