defmodule HostKit.Runner.SSH do
  @moduledoc "Stateless SSH runner backed by OTP `:ssh`."

  @behaviour HostKit.Runner

  alias HostKit.Runner.SSH.Connection

  @impl true
  def cmd(command, args, opts) do
    with_connection(opts, :command, &Connection.cmd(command, args, Keyword.put(opts, :conn, &1)))
  end

  @impl true
  def mkdir_p(path, opts) do
    with_connection(opts, :operation, &Connection.mkdir_p(path, Keyword.put(opts, :conn, &1)))
  end

  @impl true
  def write_file(path, content, opts) do
    with_connection(
      opts,
      :operation,
      &Connection.write_file(path, content, Keyword.put(opts, :conn, &1))
    )
  end

  defp with_connection(opts, error_mode, fun) do
    case Connection.open(opts) do
      {:ok, conn} ->
        run_and_close(conn, fun)

      {:error, reason} ->
        format_connect_error(error_mode, reason)
    end
  end

  defp run_and_close(conn, fun) do
    fun.(conn)
  after
    Connection.close(conn)
  end

  defp format_connect_error(:command, reason), do: {inspect(reason), 255}
  defp format_connect_error(:operation, reason), do: {:error, {:ssh_connect_failed, reason}}
end
