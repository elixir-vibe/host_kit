defmodule HostKit.Remote do
  @moduledoc "Read-only inspection of resources through a HostKit runner."

  alias HostKit.Caddy
  alias HostKit.{Firewall, Proxy, Reader.Helpers, Runner, Systemd}

  alias HostKit.Resources.{
    Account,
    Command,
    Directory,
    EnvFile,
    Exs,
    File,
    Mise,
    Package,
    Readiness,
    Shell,
    Source,
    Symlink
  }

  @spec read(struct(), map()) :: {:ok, struct() | nil} | {:error, term()}
  def read(%Account{name: name} = desired, context) do
    case cmd(context, "getent", ["passwd", name]) do
      {line, 0} -> {:ok, Helpers.account_from_passwd(line, desired)}
      {_output, 2} -> {:ok, nil}
      {output, status} -> {:error, {:getent_failed, status, output}}
    end
  end

  def read(%Directory{} = desired, context) do
    Helpers.read_directory(desired, &stat_metadata(&1, context))
  end

  def read(%File{} = desired, context) do
    Helpers.read_file(desired, &stat_metadata(&1, context), &read_file(&1, context))
  end

  def read(%EnvFile{} = desired, context) do
    Helpers.read_env_file(desired, &read(&1, context))
  end

  def read(%Symlink{} = desired, context) do
    Helpers.read_symlink(desired, &stat_metadata(&1, context), &read_link(&1, context))
  end

  def read(%Firewall{} = desired, context) do
    Helpers.read_firewall(desired, &read(&1, context))
  end

  def read(%Proxy{} = desired, context) do
    read_proxy(desired, context)
  end

  def read(%Mise{} = desired, context) do
    HostKit.Mise.read(desired, context)
  end

  def read(%Package{} = desired, context) do
    HostKit.Package.read(desired, context)
  end

  def read(%Command{} = desired, context),
    do: Helpers.read_run_resource(desired, Map.get(context, :opts, []))

  def read(%Shell{} = desired, context),
    do: Helpers.read_run_resource(desired, Map.get(context, :opts, []))

  def read(%Source{} = desired, context),
    do: HostKit.Source.Git.read(desired, Map.get(context, :opts, []))

  def read(%Readiness{} = desired, context),
    do: read_readiness(desired, Map.get(context, :opts, []))

  def read(%HostKit.Instance{} = desired, context),
    do: HostKit.Instance.Backend.read(desired, Map.get(context, :opts, []))

  def read(%Systemd.Service{name: name} = desired, context) do
    read_systemd_unit("/etc/systemd/system/#{name}", desired, context)
  end

  def read(%Systemd.Timer{name: name} = desired, context) do
    read_systemd_unit("/etc/systemd/system/#{name}", desired, context)
  end

  def read(%HostKit.Resources.ConfigFile{} = desired, context) do
    Helpers.read_config_file(desired, &read(&1, context))
  end

  def read(%HostKit.Resources.Template{} = desired, context) do
    Helpers.read_template(desired, &read(&1, context))
  end

  def read(%Exs{} = desired, context) do
    Helpers.read_exs(desired, &read(&1, context))
  end

  def read(%Caddy.Site{} = desired, context) do
    sites_dir =
      get_in(context, [
        :project,
        Access.key(:provider_configs),
        :caddy,
        Access.key(:config),
        :sites_dir
      ])

    case sites_dir do
      nil ->
        {:ok, nil}

      dir ->
        read_caddy_site(Path.join(dir, Helpers.caddy_site_filename(desired)), desired, context)
    end
  end

  def read(_resource, _context), do: {:ok, nil}

  defp read_readiness(desired, opts) do
    if HostKit.Readiness.current?(desired, opts), do: {:ok, desired}, else: {:ok, nil}
  end

  defp read_systemd_unit(path, desired, context) do
    case read_file(path, context) do
      {:ok, content} ->
        {:ok,
         %{desired | meta: Map.put(desired.meta, :content, content)} |> Helpers.mark_render()}

      {:error, :enoent} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_proxy(%Proxy{path: path} = desired, context) do
    Helpers.read_content_resource(desired, path, &read_file(&1, context))
  end

  defp read_caddy_site(path, desired, context) do
    case read_file(path, context) do
      {:ok, content} -> {:ok, %{desired | meta: Map.put(desired.meta, :content, content)}}
      {:error, :enoent} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_file(path, %{opts: opts}) do
    case HostKit.Runner.Files.read_file(path, opts) do
      {:ok, content} ->
        {:ok, content}

      {:error, {:command_failed, _command, _args, _status, output}} ->
        {:error, stat_error(output)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_link(path, context) do
    command = if sudo?(context), do: "sudo", else: "readlink"
    args = if sudo?(context), do: ["readlink", path], else: [path]

    case cmd(context, command, args) do
      {target, 0} -> {:ok, String.trim_trailing(target, "\n")}
      {output, _status} -> {:error, stat_error(output)}
    end
  end

  defp stat_metadata(path, context) do
    command = if sudo?(context), do: "sudo", else: "stat"

    args =
      if sudo?(context),
        do: ["stat", "-c", "%F:%U:%G:%a", path],
        else: ["-c", "%F:%U:%G:%a", path]

    case cmd(context, command, args) do
      {output, 0} -> Helpers.parse_stat_output(output)
      {output, _status} -> {:error, stat_error(output)}
    end
  end

  defp stat_error(output) do
    cond do
      String.contains?(output, "No such file") ->
        :enoent

      String.contains?(output, "cannot stat") and
          not String.contains?(output, "Permission denied") ->
        :enoent

      true ->
        {:remote_read_failed, output}
    end
  end

  defp cmd(%{opts: opts}, command, args) do
    runner = Keyword.get(opts, :runner, HostKit.Runner.Local)

    runner_opts =
      opts
      |> Keyword.take([:trace])
      |> Keyword.merge(stderr_to_stdout: true)

    Runner.cmd(runner, command, args, runner_opts)
  end

  defp sudo?(%{opts: opts}), do: Keyword.get(opts, :sudo, false)
end
