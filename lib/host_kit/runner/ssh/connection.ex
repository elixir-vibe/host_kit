defmodule HostKit.Runner.SSH.Connection do
  @moduledoc "Reusable OTP SSH connection runner."

  @behaviour HostKit.Runner

  @default_port 22
  @timeout 30_000
  @default_preferred_algorithms [
    kex: [
      :"curve25519-sha256",
      :"curve25519-sha256@libssh.org",
      :"ecdh-sha2-nistp256",
      :"diffie-hellman-group14-sha256"
    ]
  ]

  @opaque t :: :ssh.connection_ref()

  @spec open(keyword()) :: {:ok, t()} | {:error, term()}
  def open(opts) do
    host = Keyword.fetch!(opts, :host) |> to_charlist()
    port = Keyword.get(opts, :port, @default_port)

    :ssh.connect(host, port, ssh_opts(opts), Keyword.get(opts, :connect_timeout, @timeout))
  end

  @spec close(t()) :: :ok
  def close(conn) do
    :ssh.close(conn)
  end

  @impl true
  def cmd(command, args, opts) do
    opts
    |> Keyword.fetch!(:conn)
    |> exec(shell_join([command | args]), opts)
  end

  @impl true
  def mkdir_p(path, opts) do
    command =
      if Keyword.get(opts, :sudo, false),
        do: ["sudo", "mkdir", "-p", path],
        else: ["mkdir", "-p", path]

    case cmd("sh", ["-c", shell_join(command)], opts) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:command_failed, "mkdir", ["-p", path], status, output}}
    end
  end

  @impl true
  def write_file(path, content, opts) do
    if Keyword.get(opts, :sudo, false) do
      sudo_write_file(path, content, opts)
    else
      direct_write_file(path, content, opts)
    end
  end

  defp sudo_write_file(path, content, opts) do
    temp_path = "/tmp/host-kit-#{System.unique_integer([:positive])}"

    result =
      with :ok <- direct_write_file(temp_path, content, Keyword.put(opts, :sudo, false)),
           {_output, 0} <- cmd("sudo", ["install", "-m", "0644", temp_path, path], opts) do
        :ok
      else
        {:error, reason} ->
          {:error, reason}

        {output, status} ->
          {:error, {:command_failed, "install", [temp_path, path], status, output}}
      end

    remove_temp_file(temp_path, opts)
    result
  end

  defp direct_write_file(path, content, opts) do
    encoded = content |> IO.iodata_to_binary() |> Base.encode64()

    case cmd(
           "sh",
           ["-c", "printf %s #{shell_escape(encoded)} | base64 -d > #{shell_escape(path)}"],
           opts
         ) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:command_failed, "write_file", [path], status, output}}
    end
  end

  defp remove_temp_file(path, opts) do
    cmd("rm", ["-f", path], Keyword.put(opts, :sudo, false))
    :ok
  end

  defp exec(conn, command, opts) do
    timeout = Keyword.get(opts, :timeout, @timeout)

    with {:ok, channel} <- :ssh_connection.session_channel(conn, timeout),
         :success <- :ssh_connection.exec(conn, channel, to_charlist(command), timeout) do
      collect_exec(conn, channel, "", nil, timeout)
    else
      {:error, reason} -> {inspect(reason), 255}
      other -> {inspect(other), 255}
    end
  end

  defp collect_exec(conn, channel, output, status, timeout) do
    receive do
      {:ssh_cm, ^conn, {:data, ^channel, _type, data}} ->
        collect_exec(conn, channel, output <> to_string(data), status, timeout)

      {:ssh_cm, ^conn, {:eof, ^channel}} ->
        collect_exec(conn, channel, output, status, timeout)

      {:ssh_cm, ^conn, {:exit_status, ^channel, exit_status}} ->
        collect_exec(conn, channel, output, exit_status, timeout)

      {:ssh_cm, ^conn, {:closed, ^channel}} ->
        {output, status || 0}
    after
      timeout ->
        :ssh_connection.close(conn, channel)
        {output, 255}
    end
  end

  defp ssh_opts(opts) do
    opts
    |> Keyword.take([
      :user,
      :user_dir,
      :user_interaction,
      :silently_accept_hosts,
      :key_cb,
      :password,
      :preferred_algorithms,
      :silently_accept_hosts
    ])
    |> Enum.map(fn
      {:user, user} -> {:user, to_charlist(user)}
      {:user_dir, dir} -> {:user_dir, to_charlist(dir)}
      pair -> pair
    end)
    |> put_identity_file(opts)
    |> Keyword.put_new(:user_interaction, false)
    |> Keyword.put_new(:preferred_algorithms, @default_preferred_algorithms)
  end

  defp put_identity_file(ssh_opts, opts) do
    case Keyword.get(opts, :identity_file) do
      nil ->
        ssh_opts

      path ->
        Keyword.put(ssh_opts, :key_cb, {HostKit.Runner.SSH.IdentityKey, identity_file: path})
    end
  end

  defp shell_join(parts), do: Enum.map_join(parts, " ", &shell_escape/1)

  defp shell_escape(value) do
    value
    |> to_string()
    |> String.replace("'", "'\\''")
    |> then(&"'#{&1}'")
  end
end
