defmodule HostKit.Workspace.Agent.UnixClient do
  @moduledoc "JSON request client for workspace agents over Unix sockets."

  @behaviour HostKit.Workspace.Agent.Client

  @impl true
  def status(socket, opts), do: request(socket, %{op: :status}, opts)

  @impl true
  def exec(socket, argv, opts), do: request(socket, %{op: :exec, argv: argv}, opts)

  @impl true
  def run_checks(socket, checks, opts) do
    payload = %{op: :run_checks, checks: Enum.map(checks, &Map.from_struct/1)}

    with {:ok, results} <- request(socket, payload, opts) do
      {:ok, results |> Map.fetch!("results") |> Enum.map(&decode_result/1)}
    end
  end

  defp request(socket, payload, opts) do
    timeout = Keyword.get(opts, :timeout, 5_000)

    with {:ok, port} <- :gen_tcp.connect({:local, socket}, 0, [:binary, active: false], timeout),
         :ok <- :gen_tcp.send(port, Jason.encode!(payload) <> "\n"),
         {:ok, response} <- :gen_tcp.recv(port, 0, timeout),
         :ok <- :gen_tcp.close(port) do
      Jason.decode(response)
    end
  end

  defp decode_result(%{"check" => check, "status" => "ok", "observed" => observed}) do
    HostKit.Monitor.Result.ok(HostKit.Monitor.Check.new(atomize_keys(check)), observed)
  end

  defp decode_result(%{"check" => check, "reason" => reason, "observed" => observed}) do
    HostKit.Monitor.Result.error(HostKit.Monitor.Check.new(atomize_keys(check)), reason, observed)
  end

  defp atomize_keys(map), do: Map.new(map, fn {key, value} -> {String.to_atom(key), value} end)
end
