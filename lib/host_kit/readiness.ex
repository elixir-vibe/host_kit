defmodule HostKit.Readiness do
  @moduledoc "Readiness check execution for HostKit resources."

  alias HostKit.Readiness.{HTTP, Systemd}
  alias HostKit.Resources.Readiness
  alias HostKit.SystemdRuntime

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
        restart_units(units, readiness, opts)
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

  defp check_all(%Readiness{checks: checks}, opts) do
    errors =
      checks
      |> Enum.map(&check_one(&1, opts))
      |> Enum.reject(&match?(:ok, &1))

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp restart_units(units, readiness, opts) do
    Enum.reduce_while(units, :ok, fn unit, :ok ->
      emit_service_restart(opts, readiness, unit, :service_restart_started)

      case SystemdRuntime.restart(unit, opts) do
        :ok ->
          emit_service_restart(opts, readiness, unit, :service_restart_finished)
          {:cont, :ok}

        {:error, reason} = error ->
          emit_service_restart(opts, readiness, unit, :service_failed, reason)
          {:halt, error}
      end
    end)
  end

  defp check_one(%Systemd{unit: unit, state: :active}, opts) do
    case SystemdRuntime.active?(unit, opts) do
      :ok -> :ok
      {:error, reason} -> {%Systemd{unit: unit, state: :active}, {:error, reason}}
    end
  end

  defp check_one(%HTTP{} = http, _opts) do
    url = HTTP.url(http)

    case Req.get(url, retry: false, receive_timeout: 5_000) do
      {:ok, %{status: status, body: body}} when status == http.expect_status ->
        check_http_body(http, body)

      {:ok, %{status: status}} ->
        {http, {:error, {:unexpected_http_status, url, http.expect_status, status}}}

      {:error, reason} ->
        {http, {:error, {:http_request_failed, url, reason}}}
    end
  end

  defp check_http_body(%HTTP{expect_body: nil}, _body), do: :ok

  defp check_http_body(%HTTP{expect_body: expected} = http, body) do
    if body |> body_text() |> String.contains?(expected) do
      :ok
    else
      {http, {:error, {:http_body_missing_text, HTTP.url(http), expected}}}
    end
  end

  defp body_text(body) when is_binary(body), do: body

  defp body_text(body) do
    Jason.encode!(body)
  rescue
    _exception -> inspect(body)
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
        emit_apply(opts, :health_check_started, readiness, details: %{url: HTTP.url(http)})
    end)
  end

  defp emit_check_passed(%Readiness{checks: checks} = readiness, opts) do
    Enum.each(checks, fn
      %Systemd{} = systemd ->
        emit_service_restart(opts, readiness, systemd, :service_active)

      %HTTP{} = http ->
        emit_apply(opts, :health_check_passed, readiness, details: %{url: HTTP.url(http)})
    end)
  end

  defp emit_check_failed(%Readiness{checks: checks} = readiness, opts, reason) do
    Enum.each(checks, fn
      %Systemd{} = systemd ->
        emit_service_restart(opts, readiness, systemd, :service_failed, reason)

      %HTTP{} = http ->
        emit_apply(opts, :health_check_failed, readiness,
          reason: reason,
          details: %{url: HTTP.url(http)}
        )
    end)
  end

  defp emit_http_waiting(%Readiness{checks: checks} = readiness, opts, details) do
    Enum.each(checks, fn
      %HTTP{} = http ->
        emit_apply(opts, :health_check_waiting, readiness,
          details: Map.merge(details, %{url: HTTP.url(http)})
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
end
