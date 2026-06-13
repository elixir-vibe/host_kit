defmodule HostKit.Workspace.Agent.UnixClient do
  @moduledoc "Erlang external term format client for workspace agents over Unix sockets."

  @behaviour HostKit.Workspace.Agent.Client

  @impl true
  def status(socket, opts) do
    with {:ok, {:ok, status}} <- request(socket, :status, opts), do: {:ok, status}
  end

  @impl true
  def exec(socket, argv, opts) do
    with {:ok, {:ok, result}} <- request(socket, {:exec, argv}, opts), do: {:ok, result}
  end

  @impl true
  def run_checks(socket, checks, opts) do
    payload = {:run_checks, checks}

    with {:ok, {:ok, results}} <- request(socket, payload, opts) do
      {:ok, Enum.map(results, &decode_result/1)}
    end
  end

  defp request(socket, payload, opts) do
    timeout = Keyword.get(opts, :timeout, 5_000)

    with {:ok, port} <-
           :gen_tcp.connect({:local, socket}, 0, [:binary, active: false, packet: 4], timeout),
         :ok <- :gen_tcp.send(port, :erlang.term_to_binary(payload)),
         {:ok, response} <- :gen_tcp.recv(port, 0, timeout),
         :ok <- :gen_tcp.close(port) do
      {:ok, :erlang.binary_to_term(response, [:safe])}
    end
  end

  defp decode_result(%HostKit.Monitor.Result{} = result), do: result
  defp decode_result({:ok, check, observed}), do: HostKit.Monitor.Result.ok(check, observed)

  defp decode_result({:error, check, reason, observed}),
    do: HostKit.Monitor.Result.error(check, reason, observed)
end
