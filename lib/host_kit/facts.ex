defmodule HostKit.Facts do
  @moduledoc "Lightweight host fact collection for audit/introspection workflows."

  alias HostKit.Target

  @facts [:os, :users, :systemd, :ports]

  @type fact :: :os | :users | :systemd | :ports

  @doc "Collects selected host facts through the configured HostKit runner."
  @spec collect(Target.t() | keyword(), keyword()) :: {:ok, map()} | {:error, term()}
  def collect(target_or_opts \\ [], opts \\ [])

  def collect(%Target{} = target, opts), do: collect(Target.opts(target), opts)

  def collect(opts, collect_opts) when is_list(opts) and is_list(collect_opts) do
    only = Keyword.get(collect_opts, :only, Keyword.get(opts, :only, @facts))
    opts = Keyword.delete(opts, :only)
    runner = Keyword.get(opts, :runner, HostKit.Runner.Local)

    {:ok,
     only
     |> Enum.filter(&(&1 in @facts))
     |> Map.new(fn fact -> {fact, collect_fact(fact, runner, opts)} end)}
  end

  defp collect_fact(:os, runner, opts) do
    %{
      os_release: read_os_release(runner, opts),
      kernel: successful_cmd(runner, "uname", ["-sr"], opts)
    }
  end

  defp collect_fact(:users, runner, opts) do
    runner
    |> successful_cmd("getent", ["passwd"], opts)
    |> String.split("\n", trim: true)
    |> Enum.map(fn line -> line |> String.split(":", parts: 2) |> hd() end)
  end

  defp collect_fact(:systemd, runner, opts) do
    %{
      version: successful_cmd(runner, "systemctl", ["--version"], opts) |> first_line(),
      failed_units:
        successful_cmd(runner, "systemctl", ["--failed", "--plain", "--no-legend"], opts)
    }
  end

  defp collect_fact(:ports, runner, opts) do
    successful_cmd(runner, "ss", ["-ltnp"], opts)
  end

  defp read_os_release(runner, opts) do
    runner
    |> successful_cmd("sh", ["-c", "cat /etc/os-release 2>/dev/null || true"], opts)
    |> String.split("\n", trim: true)
    |> Map.new(fn line ->
      case String.split(line, "=", parts: 2) do
        [key, value] -> {key, String.trim(value, "\"")}
        [key] -> {key, ""}
      end
    end)
  end

  defp successful_cmd(runner, command, args, opts) do
    case HostKit.Runner.cmd(runner, command, args, opts) do
      {output, 0} -> String.trim_trailing(output)
      {_output, _status} -> ""
    end
  end

  defp first_line(output), do: output |> String.split("\n", trim: true) |> List.first()
end
