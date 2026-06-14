defmodule HostKit.Runner.Files do
  @moduledoc "Filesystem helpers over HostKit runners."

  alias HostKit.Runner

  @spec read_file(Path.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def read_file(path, opts \\ []) do
    if local_without_sudo?(opts) do
      File.read(path)
    else
      read_file_through_runner(path, opts)
    end
  end

  @spec mkdir_p(Path.t(), keyword()) :: :ok | {:error, term()}
  def mkdir_p(path, opts \\ []) do
    Runner.mkdir_p(runner(opts), path, opts)
  end

  @spec write_file(Path.t(), iodata(), keyword()) :: :ok | {:error, term()}
  def write_file(path, content, opts \\ []) do
    Runner.write_file(runner(opts), path, content, opts)
  end

  defp local_without_sudo?(opts) do
    runner(opts) == HostKit.Runner.Local and not Keyword.get(opts, :sudo, false)
  end

  defp read_file_through_runner(path, opts) do
    case Runner.cmd(
           runner(opts),
           "sh",
           ["-c", read_script(path, opts)],
           Keyword.merge(opts, stderr_to_stdout: true)
         ) do
      {content, 0} -> decode_content(content)
      {output, status} -> {:error, {:command_failed, "base64", [path], status, output}}
    end
  end

  defp read_script(path, opts) do
    command = if Keyword.get(opts, :sudo, false), do: "sudo base64", else: "base64"
    command <> " " <> HostKit.Shell.escape(path)
  end

  defp decode_content(content) do
    content
    |> String.replace(~r/\s+/, "")
    |> Base.decode64()
  end

  defp runner(opts), do: Keyword.get(opts, :runner, HostKit.Runner.Local)
end
