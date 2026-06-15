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

    opts =
      opts
      |> Keyword.delete(:only)
      |> Keyword.delete(:reader)
      |> Keyword.delete(:target)
      |> Keyword.delete(:sudo)

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
    |> Enum.map(&parse_passwd_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp collect_fact(:systemd, runner, opts) do
    %{
      version: successful_cmd(runner, "systemctl", ["--version"], opts) |> first_line(),
      failed_units:
        runner
        |> successful_cmd("systemctl", ["--failed", "--plain", "--no-legend"], opts)
        |> parse_failed_units()
    }
  end

  defp collect_fact(:ports, runner, opts) do
    runner
    |> successful_cmd("ss", ["-ltnp"], opts)
    |> parse_ports()
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

  defp parse_passwd_line(line) do
    case String.split(line, ":") do
      [name, _password, uid, gid, gecos, home, shell] ->
        %{
          name: name,
          uid: parse_int(uid),
          gid: parse_int(gid),
          gecos: gecos,
          home: home,
          shell: shell
        }

      _other ->
        nil
    end
  end

  defp parse_failed_units(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case String.split(line, ~r/\s+/, parts: 5) do
        [unit, load, active, sub, description] ->
          %{unit: unit, load: load, active: active, sub: sub, description: description}

        [unit, load, active, sub] ->
          %{unit: unit, load: load, active: active, sub: sub, description: ""}

        _other ->
          %{raw: line}
      end
    end)
  end

  defp parse_ports(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "State"))
    |> Enum.map(&parse_port_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_port_line(line) do
    case Regex.run(~r/^LISTEN\s+\S+\s+\S+\s+(?<local>\S+)(?:\s+\S+)?\s*(?<process>.*)$/, line,
           capture: :all_names
         ) do
      [local, process] ->
        {address, port} = split_address_port(local)
        %{address: address, port: port, process: String.trim(process)}

      _other ->
        nil
    end
  end

  defp split_address_port(local) do
    case Regex.run(~r/^\[(?<address>.*)\]:(?<port>\d+)$/, local, capture: :all_names) do
      [address, port] -> {address, parse_int(port)}
      _other -> split_plain_address_port(local)
    end
  end

  defp split_plain_address_port(local) do
    case String.split(local, ":") do
      [port] -> {"*", parse_int(port)}
      parts -> {parts |> Enum.drop(-1) |> Enum.join(":"), parts |> List.last() |> parse_int()}
    end
  end

  defp successful_cmd(runner, command, args, opts) do
    case HostKit.Runner.cmd(runner, command, args, opts) do
      {output, 0} -> String.trim_trailing(output)
      {_output, _status} -> ""
    end
  end

  defp parse_int(value) do
    case Integer.parse(to_string(value)) do
      {int, ""} -> int
      _other -> value
    end
  end

  defp first_line(output), do: output |> String.split("\n", trim: true) |> List.first()
end
