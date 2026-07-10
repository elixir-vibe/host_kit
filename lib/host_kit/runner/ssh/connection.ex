defmodule HostKit.Runner.SSH.Connection do
  @moduledoc "Reusable OTP SSH connection runner."

  @behaviour HostKit.Runner

  alias HostKit.Runner.SSH.Retry

  @default_port 22
  @timeout 30_000
  @max_output 1_000_000
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
    timeout = Keyword.get(opts, :connect_timeout, @timeout)
    connect_fun = Keyword.get(opts, :connect_fun, &:ssh.connect/4)

    retry_open(
      connect_fun,
      host,
      port,
      ssh_opts(opts),
      timeout,
      Retry.normalize(opts[:retry]),
      opts
    )
  end

  @spec close(t()) :: :ok
  def close(conn) do
    :ssh.close(conn)
  end

  @impl true
  def cmd(command, args, opts) do
    opts
    |> Keyword.fetch!(:conn)
    |> exec(command_line(command, args, opts), opts)
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
    source_path = HostKit.Runner.Files.temporary_path("/tmp/host-kit")
    target_path = HostKit.Runner.Files.temporary_path(path)
    install_args = HostKit.Runner.Files.install_args(source_path, target_path, opts)
    user_opts = Keyword.put(opts, :sudo, false)

    move_args = ["mv", "-f", "--", target_path, path]

    try do
      with :ok <- direct_write_file(source_path, content, Keyword.put(user_opts, :mode, 0o600)),
           {:install, {_output, 0}} <- {:install, cmd("sudo", install_args, opts)},
           {:move, {_output, 0}} <- {:move, cmd("sudo", move_args, opts)} do
        :ok
      else
        {:error, reason} ->
          {:error, reason}

        {:install, {output, status}} ->
          HostKit.Runner.Files.command_error("install", install_args, status, output)

        {:move, {output, status}} ->
          HostKit.Runner.Files.command_error("mv", move_args, status, output)
      end
    after
      cleanup("rm", ["-f", "--", source_path], user_opts)
      cleanup("sudo", ["rm", "-f", "--", target_path], opts)
    end
  end

  defp direct_write_file(path, content, opts) do
    temp_path = HostKit.Runner.Files.temporary_path(path)
    encoded = content |> IO.iodata_to_binary() |> Base.encode64()
    mode = format_mode(Keyword.get(opts, :mode) || 0o600)
    encoded = HostKit.Shell.escape(encoded)
    escaped_temp_path = HostKit.Shell.escape(temp_path)
    escaped_path = HostKit.Shell.escape(path)

    script =
      "umask 077; set -C; " <>
        "printf %s #{encoded} | base64 -d > #{escaped_temp_path} && " <>
        "chmod #{mode} #{escaped_temp_path} && " <>
        "mv -f -- #{escaped_temp_path} #{escaped_path}"

    try do
      case cmd("sh", ["-c", script], opts) do
        {_output, 0} -> :ok
        {output, status} -> {:error, {:command_failed, "write_file", [path], status, output}}
      end
    after
      cleanup("rm", ["-f", "--", temp_path], Keyword.put(opts, :sudo, false))
    end
  end

  defp cleanup(command, args, opts) do
    cmd(command, args, opts)
    :ok
  rescue
    _error in [ErlangError, ArgumentError] -> :ok
  end

  defp exec(conn, command, opts) do
    timeout = Keyword.get(opts, :timeout, @timeout)

    with {:ok, channel} <- :ssh_connection.session_channel(conn, timeout),
         :success <- :ssh_connection.exec(conn, channel, to_charlist(command), timeout) do
      max_output = Keyword.get(opts, :max_output) || @max_output
      collect_exec(conn, channel, [], 0, nil, timeout, max_output)
    else
      {:error, reason} -> {inspect(reason), 255}
      other -> {inspect(other), 255}
    end
  end

  defp collect_exec(conn, channel, output, size, status, timeout, max_output) do
    receive do
      {:ssh_cm, ^conn, {:data, ^channel, _type, data}} ->
        {output, size} = append_output(output, size, data, max_output)
        collect_exec(conn, channel, output, size, status, timeout, max_output)

      {:ssh_cm, ^conn, {:eof, ^channel}} ->
        collect_exec(conn, channel, output, size, status, timeout, max_output)

      {:ssh_cm, ^conn, {:exit_status, ^channel, exit_status}} ->
        collect_exec(conn, channel, output, size, exit_status, timeout, max_output)

      {:ssh_cm, ^conn, {:closed, ^channel}} ->
        {output |> Enum.reverse() |> IO.iodata_to_binary(), status || 0}
    after
      timeout ->
        :ssh_connection.close(conn, channel)
        {output |> Enum.reverse() |> IO.iodata_to_binary(), 255}
    end
  end

  defp append_output(output, size, _data, max) when size >= max, do: {output, size}

  defp append_output(output, size, data, max) do
    data = IO.iodata_to_binary(data)
    keep = min(byte_size(data), max - size)
    {[binary_part(data, 0, keep) | output], size + keep}
  end

  defp format_mode(mode), do: mode |> Integer.to_string(8) |> String.pad_leading(4, "0")

  defp retry_open(connect_fun, host, port, ssh_opts, timeout, retry, opts, attempt \\ 1) do
    case connect_fun.(host, port, ssh_opts, timeout) do
      {:ok, _conn} = ok ->
        if attempt > 1 do
          emit_transport_retry(opts, :transport_retry_succeeded,
            attempt: attempt,
            attempts: retry.attempts
          )
        end

        ok

      {:error, reason} when attempt < retry.attempts ->
        delay = Retry.delay(retry, attempt)

        emit_transport_retry(opts, :transport_retry_started,
          attempt: attempt + 1,
          attempts: retry.attempts,
          delay_ms: delay,
          reason: reason
        )

        if delay > 0, do: Process.sleep(delay)
        retry_open(connect_fun, host, port, ssh_opts, timeout, retry, opts, attempt + 1)

      {:error, reason} = error ->
        if retry.attempts > 1 do
          emit_transport_retry(opts, :transport_retry_exhausted,
            attempt: attempt,
            attempts: retry.attempts,
            reason: reason
          )
        end

        error
    end
  end

  defp emit_transport_retry(opts, type, details) do
    details = details |> Map.new() |> Map.put(:transport, :ssh)
    HostKit.Apply.Events.emit(opts, type, details: details)
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
      {:password, password} -> {:password, to_charlist(password)}
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

  defp command_line(command, args, opts) do
    command = shell_join([command | args])

    [cd_prefix(Keyword.get(opts, :cd)), env_prefix(Keyword.get(opts, :env)), command]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp cd_prefix(nil), do: ""
  defp cd_prefix(path), do: "cd #{HostKit.Shell.escape(path)} &&"

  defp env_prefix(nil), do: ""
  defp env_prefix(env), do: HostKit.Shell.env(env)

  defp shell_join(parts), do: HostKit.Shell.join(parts)
end
