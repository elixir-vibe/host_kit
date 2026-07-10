defmodule HostKit.Backup.Archive do
  @moduledoc "Archive operations for HostKit backups. Uses explicit argv, never shell scripts."

  @spec create(Path.t(), [Path.t()], keyword()) :: :ok | {:error, term()}
  def create(archive, members, opts \\ []) do
    runner = Keyword.get(opts, :runner, &System.cmd/3)
    args = ["-C", "/", "-czf", archive, "--" | members]

    case runner.("tar", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:tar_failed, status, output}}
    end
  end

  @spec members(Path.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def members(archive, opts \\ []) do
    runner = Keyword.get(opts, :runner, &System.cmd/3)

    case runner.("tar", ["-tzf", archive], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok,
         output |> String.split("\n", trim: true) |> Enum.map(&String.trim_trailing(&1, "/"))}

      {output, status} ->
        {:error, {:tar_list_failed, status, output}}
    end
  end
end
