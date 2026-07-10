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

  @doc false
  def install_args(source, target, opts) do
    ["install", "-m", format_mode(Keyword.get(opts, :mode) || 0o600)]
    |> maybe_add_install_option("-o", Keyword.get(opts, :owner))
    |> maybe_add_install_option("-g", Keyword.get(opts, :group))
    |> Kernel.++(["--", source, target])
  end

  @doc false
  def command_error(command, args, status, output),
    do: {:error, {:command_failed, command, args, status, output}}

  @doc false
  def temporary_path(path) do
    suffix = :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
    "#{path}.hostkit-#{suffix}"
  end

  defp maybe_add_install_option(args, _option, nil), do: args
  defp maybe_add_install_option(args, option, value), do: args ++ [option, value]
  defp format_mode(mode), do: mode |> Integer.to_string(8) |> String.pad_leading(4, "0")

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
