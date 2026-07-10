defmodule HostKit.Runner.Local do
  @moduledoc "Local command runner for HostKit operations."

  @behaviour HostKit.Runner

  @system_cmd_opts [
    :arg0,
    :cd,
    :env,
    :into,
    :parallelism,
    :stderr_to_stdout,
    :windows_verbatim_args
  ]

  @impl true
  def cmd(command, args, opts \\ []) do
    opts = normalize_opts(opts)
    cmd_fun = Keyword.get(opts, :cmd_fun, &System.cmd/3)
    cmd_fun.(command, args, system_cmd_opts(opts))
  end

  defp normalize_opts(opts) do
    case Keyword.fetch(opts, :env) do
      {:ok, env} when is_map(env) -> Keyword.put(opts, :env, Map.to_list(env))
      _other -> opts
    end
  end

  defp system_cmd_opts(opts), do: Keyword.take(opts, @system_cmd_opts)

  @impl true
  def mkdir_p(path, opts \\ []) do
    if Keyword.get(opts, :sudo, false) do
      case cmd("sudo", ["mkdir", "-p", path], opts) do
        {_output, 0} -> :ok
        {output, status} -> {:error, {:command_failed, "mkdir", ["-p", path], status, output}}
      end
    else
      Elixir.File.mkdir_p(path)
    end
  end

  @impl true
  def write_file(path, content, opts \\ []) do
    if Keyword.get(opts, :sudo, false) do
      sudo_write_file(path, content, opts)
    else
      atomic_write_file(path, content, opts)
    end
  end

  defp atomic_write_file(path, content, opts) do
    temp_path = HostKit.Runner.Files.temporary_path(path)

    try do
      with {:ok, file} <- Elixir.File.open(temp_path, [:write, :binary, :exclusive]),
           :ok <- write_open_file(file, temp_path, content, Keyword.get(opts, :mode) || 0o600) do
        Elixir.File.rename(temp_path, path)
      end
    after
      Elixir.File.rm(temp_path)
    end
  end

  defp write_open_file(file, path, content, mode) do
    with :ok <- Elixir.File.chmod(path, mode) do
      IO.binwrite(file, content)
    end
  after
    Elixir.File.close(file)
  end

  defp sudo_write_file(path, content, opts) do
    source_path = HostKit.Runner.Files.temporary_path(Path.join(System.tmp_dir!(), "host-kit"))
    target_path = HostKit.Runner.Files.temporary_path(path)
    install_args = HostKit.Runner.Files.install_args(source_path, target_path, opts)

    move_args = ["mv", "-f", "--", target_path, path]

    try do
      with :ok <- atomic_write_file(source_path, content, mode: 0o600),
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
      Elixir.File.rm(source_path)
      cleanup_sudo(target_path, opts)
    end
  end

  defp cleanup_sudo(path, opts) do
    cmd("sudo", ["rm", "-f", "--", path], opts)
    :ok
  rescue
    _error in [ErlangError, ArgumentError] -> :ok
  end
end
