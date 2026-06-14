defmodule HostKit.Runner.Ops do
  @moduledoc "Small filesystem and command helpers around HostKit runners."

  alias HostKit.Runner

  @spec chown(Path.t(), String.t() | nil, String.t() | nil, keyword()) :: :ok | {:error, term()}
  def chown(_path, nil, nil, _opts), do: :ok

  def chown(path, owner, group, opts) do
    spec = [owner || "", group || ""] |> Enum.join(":") |> String.trim_trailing(":")
    cmd(opts, "chown", [spec, path])
  end

  @spec chmod(Path.t(), non_neg_integer() | nil, keyword()) :: :ok | {:error, term()}
  def chmod(_path, nil, _opts), do: :ok

  def chmod(path, mode, opts) do
    cmd(opts, "chmod", [Integer.to_string(mode, 8), path])
  end

  @spec cmd(keyword(), String.t(), [String.t()], keyword()) :: :ok | {:error, term()}
  def cmd(opts, command, args, command_opts \\ []) do
    {command, args} = maybe_sudo(command, args, opts)

    case Runner.cmd(
           runner(opts),
           command,
           args,
           command_run_opts(opts, command_opts)
         ) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:command_failed, command, args, status, output}}
    end
  end

  @spec runner(keyword()) :: module() | {module(), keyword()}
  def runner(opts), do: Keyword.get(opts, :runner, HostKit.Runner.Local)

  defp command_run_opts(opts, command_opts) do
    opts
    |> Keyword.take([:trace])
    |> Keyword.merge(stderr_to_stdout: true)
    |> Keyword.merge(command_opts)
  end

  defp maybe_sudo(command, args, opts) do
    if Keyword.get(opts, :sudo, false), do: {"sudo", [command | args]}, else: {command, args}
  end
end
