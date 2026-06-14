defmodule HostKit.Runner do
  @moduledoc "Command execution boundary for HostKit apply/deploy operations."

  @type command :: String.t()
  @type args :: [String.t()]
  @type opts :: keyword()
  @type result :: {String.t(), non_neg_integer()}

  @callback cmd(command(), args(), opts()) :: result()
  @callback mkdir_p(Path.t(), opts()) :: :ok | {:error, term()}
  @callback write_file(Path.t(), iodata(), opts()) :: :ok | {:error, term()}

  @spec cmd(module() | {module(), keyword()}, command(), args(), opts()) :: result()
  def cmd({runner, runner_opts}, command, args, opts) when is_atom(runner) do
    merged_opts = Keyword.merge(runner_opts, opts)
    traced_cmd({runner, runner_opts}, command, args, merged_opts)
  end

  def cmd(runner, command, args, opts) when is_atom(runner) do
    traced_cmd(runner, command, args, opts)
  end

  defp traced_cmd(runner, command, args, opts) do
    metadata = %{runner: runner_module(runner), command: command, args: args}
    native_started = System.monotonic_time()
    ms_started = System.monotonic_time(:millisecond)

    HostKit.Telemetry.execute(
      [:runner, :cmd, :start],
      %{system_time: System.system_time()},
      metadata
    )

    result = runner_module(runner).cmd(command, args, opts)
    native_duration = System.monotonic_time() - native_started
    ms_duration = System.monotonic_time(:millisecond) - ms_started
    maybe_trace_command(opts, command, args, result, ms_duration)

    HostKit.Telemetry.execute(
      [:runner, :cmd, :stop],
      %{duration: native_duration},
      Map.put(metadata, :status, command_status(result))
    )

    result
  end

  defp runner_module({runner, _opts}), do: runner
  defp runner_module(runner), do: runner

  defp command_status({_output, status}), do: status

  defp format_command("sh", ["-c", script]) when is_binary(script) do
    "sh -c #{format_script(script)}"
  end

  defp format_command("sudo", ["sh", "-c", script]) when is_binary(script) do
    "sudo sh -c #{format_script(script)}"
  end

  defp format_command(command, args) do
    [command | args]
    |> Enum.map_join(" ", &format_arg/1)
    |> truncate(220)
  end

  defp format_script(script) do
    hash = :crypto.hash(:sha256, script) |> Base.encode16(case: :lower) |> binary_part(0, 12)
    lines = script |> String.split("\n") |> length()
    first_line = script |> String.split("\n", parts: 2) |> hd() |> String.trim() |> truncate(80)
    "<script sha256=#{hash} lines=#{lines} first=#{inspect(first_line)}>"
  end

  defp format_arg(arg) when is_binary(arg),
    do: if(String.contains?(arg, " "), do: inspect(arg), else: arg)

  defp format_arg(arg), do: inspect(arg)

  defp truncate(value, max) when byte_size(value) > max, do: binary_part(value, 0, max) <> "…"
  defp truncate(value, _max), do: value

  defp maybe_trace_command(opts, command, args, {_output, status}, duration) do
    case Keyword.get(opts, :trace) do
      pid when is_pid(pid) ->
        send(pid, {:hostkit_runner_trace, command, args, status, duration})

      :stdio ->
        IO.puts("[hostkit:cmd] #{duration}ms status=#{status} #{format_command(command, args)}")

      _other ->
        :ok
    end
  end

  @spec mkdir_p(module() | {module(), keyword()}, Path.t(), opts()) :: :ok | {:error, term()}
  def mkdir_p({runner, runner_opts}, path, opts) when is_atom(runner) do
    runner.mkdir_p(path, Keyword.merge(runner_opts, opts))
  end

  def mkdir_p(runner, path, opts) when is_atom(runner) do
    runner.mkdir_p(path, opts)
  end

  @spec write_file(module() | {module(), keyword()}, Path.t(), iodata(), opts()) ::
          :ok | {:error, term()}
  def write_file({runner, runner_opts}, path, content, opts) when is_atom(runner) do
    runner.write_file(path, content, Keyword.merge(runner_opts, opts))
  end

  def write_file(runner, path, content, opts) when is_atom(runner) do
    runner.write_file(path, content, opts)
  end
end
