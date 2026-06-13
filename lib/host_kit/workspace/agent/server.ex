defmodule HostKit.Workspace.Agent.Server do
  @moduledoc "Workspace agent server speaking Erlang external terms over a Unix socket."

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @impl true
  def init(opts) do
    socket = Keyword.fetch!(opts, :socket)
    File.rm(socket)
    File.mkdir_p!(Path.dirname(socket))

    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, active: false, packet: 4, ifaddr: {:local, socket}])

    state = %{
      socket: socket,
      listen: listen,
      workspace: Keyword.get(opts, :workspace, File.cwd!()),
      timeout: Keyword.get(opts, :timeout, 30_000),
      max_output: Keyword.get(opts, :max_output, 64_000)
    }

    send(self(), :accept)
    {:ok, state}
  end

  @impl true
  def handle_info(:accept, state) do
    case :gen_tcp.accept(state.listen, 0) do
      {:ok, client} ->
        Task.start(fn -> serve(client, state) end)
        send(self(), :accept)
        {:noreply, state}

      {:error, :timeout} ->
        send(self(), :accept)
        {:noreply, state}

      {:error, _reason} ->
        {:stop, :accept_failed, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    :gen_tcp.close(state.listen)
    File.rm(state.socket)
    :ok
  end

  defp serve(client, state) do
    response =
      with {:ok, payload} <- :gen_tcp.recv(client, 0, state.timeout) do
        payload
        |> :erlang.binary_to_term([:safe])
        |> handle_request(state)
      end

    :gen_tcp.send(client, :erlang.term_to_binary(response))
    :gen_tcp.close(client)
  end

  defp handle_request(:status, state) do
    {:ok, %{status: :ok, workspace: state.workspace, cwd: File.cwd!()}}
  end

  defp handle_request({:exec, argv}, state) do
    run_command(argv, state)
  end

  defp handle_request({:run_checks, checks}, state) do
    {:ok, Enum.map(checks, &run_check(&1, state))}
  end

  defp handle_request(other, _state), do: {:error, {:unknown_request, other}}

  defp run_check(%HostKit.Monitor.Check{type: :port} = check, _state) do
    port =
      check.port || Keyword.get(check.expect, :port) || get_in(check.meta, [:port]) ||
        check.target

    if listening?(port) do
      HostKit.Monitor.Result.ok(check, %{port: port, listening: true})
    else
      HostKit.Monitor.Result.error(check, :not_listening, %{port: port, listening: false})
    end
  end

  defp run_check(%HostKit.Monitor.Check{type: :git} = check, state) do
    case run_command(["git", "status", "--porcelain"], %{state | max_output: 16_000}) do
      {:ok, %{exit_status: 0, stdout: ""}} ->
        HostKit.Monitor.Result.ok(check, %{clean: true})

      {:ok, %{exit_status: 0, stdout: output}} ->
        HostKit.Monitor.Result.error(check, :dirty, %{clean: false, output: output})

      {:ok, result} ->
        HostKit.Monitor.Result.error(check, {:command_failed, result.exit_status}, result)

      {:error, reason} ->
        HostKit.Monitor.Result.error(check, reason)
    end
  end

  defp run_check(%HostKit.Monitor.Check{type: :mix} = check, state) do
    task = check.task || Keyword.get(check.expect, :task) || get_in(check.meta, [:task]) || "test"

    case run_command(["mix", task], state) do
      {:ok, %{exit_status: 0} = result} ->
        HostKit.Monitor.Result.ok(check, result)

      {:ok, result} ->
        HostKit.Monitor.Result.error(check, {:command_failed, result.exit_status}, result)

      {:error, reason} ->
        HostKit.Monitor.Result.error(check, reason)
    end
  end

  defp run_check(%HostKit.Monitor.Check{} = check, _state),
    do: HostKit.Monitor.Result.error(check, {:unsupported_inside_check, check.type})

  defp run_command([command | args], state) do
    task =
      Task.async(fn -> System.cmd(command, args, cd: state.workspace, stderr_to_stdout: true) end)

    case Task.yield(task, state.timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, status}} ->
        {:ok, %{exit_status: status, stdout: truncate(output, state.max_output)}}

      nil ->
        {:error, :timeout}
    end
  rescue
    error in [ErlangError, RuntimeError, ArgumentError] -> {:error, error}
  end

  defp run_command(_argv, _state), do: {:error, :invalid_command}

  defp listening?(port) when is_integer(port) do
    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 500) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _reason} ->
        false
    end
  end

  defp listening?(_port), do: false

  defp truncate(output, max) when byte_size(output) <= max, do: output
  defp truncate(output, max), do: binary_part(output, 0, max)
end
