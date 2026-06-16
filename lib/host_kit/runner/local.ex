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
      Elixir.File.write(path, content)
    end
  end

  defp sudo_write_file(path, content, opts) do
    temp_path = Path.join(System.tmp_dir!(), "host-kit-#{System.unique_integer([:positive])}")

    result =
      with :ok <- Elixir.File.write(temp_path, content),
           {_output, 0} <- cmd("sudo", ["install", "-m", "0644", temp_path, path], opts) do
        :ok
      else
        {:error, reason} ->
          {:error, reason}

        {output, status} ->
          {:error, {:command_failed, "install", [temp_path, path], status, output}}
      end

    Elixir.File.rm(temp_path)
    result
  end
end
