defmodule HostKit.Local do
  @moduledoc "Read-only inspection of resources on the local host."

  alias HostKit.{Caddy, Firewall, Proxy}
  alias HostKit.Reader.Helpers

  alias HostKit.Resources.{
    Account,
    Command,
    Directory,
    EnvFile,
    File,
    Mise,
    Package,
    Readiness,
    Shell,
    Source,
    Symlink
  }

  alias HostKit.Systemd

  @spec read(struct()) :: {:ok, struct() | nil} | {:error, term()}
  def read(%Account{name: name} = desired) do
    case System.cmd("getent", ["passwd", name], stderr_to_stdout: true) do
      {line, 0} -> {:ok, Helpers.account_from_passwd(line, desired)}
      {_output, 2} -> {:ok, nil}
      {output, status} -> {:error, {:getent_failed, status, output}}
    end
  end

  def read(%Directory{path: path} = desired) do
    with {:stat, {:ok, %Elixir.File.Stat{type: :directory}}} <- {:stat, Elixir.File.stat(path)},
         {:metadata, {:ok, metadata}} <- {:metadata, stat_metadata(path)} do
      {:ok,
       %Directory{desired | owner: metadata.owner, group: metadata.group, mode: metadata.mode}}
    else
      {:stat, {:ok, %Elixir.File.Stat{type: type}}} -> {:error, {:not_directory, path, type}}
      {:stat, {:error, :enoent}} -> {:ok, nil}
      {:stat, {:error, reason}} -> {:error, reason}
      {:metadata, {:error, reason}} -> {:error, reason}
    end
  end

  def read(%File{path: path} = desired) do
    with {:stat, {:ok, %Elixir.File.Stat{type: :regular}}} <- {:stat, Elixir.File.stat(path)},
         {:metadata, {:ok, metadata}} <- {:metadata, stat_metadata(path)},
         {:content, {:ok, content}} <- {:content, read_file(path, %{})} do
      {:ok,
       %File{
         desired
         | content: content,
           owner: metadata.owner,
           group: metadata.group,
           mode: metadata.mode
       }}
    else
      {:stat, {:ok, %Elixir.File.Stat{type: type}}} -> {:error, {:not_file, path, type}}
      {:stat, {:error, :enoent}} -> {:ok, nil}
      {:stat, {:error, reason}} -> {:error, reason}
      {:metadata, {:error, reason}} -> {:error, reason}
      {:content, {:error, reason}} -> {:error, reason}
    end
  end

  def read(%EnvFile{} = desired) do
    Helpers.read_env_file(desired, &read/1)
  end

  def read(%Symlink{path: path} = desired) do
    with {:stat, {:ok, %Elixir.File.Stat{type: :symlink}}} <- {:stat, Elixir.File.lstat(path)},
         {:metadata, {:ok, metadata}} <- {:metadata, stat_metadata(path)},
         {:target, {:ok, target}} <- {:target, Elixir.File.read_link(path)} do
      {:ok, %Symlink{desired | to: target, owner: metadata.owner, group: metadata.group}}
    else
      {:stat, {:ok, %Elixir.File.Stat{type: type}}} -> {:error, {:not_symlink, path, type}}
      {:stat, {:error, :enoent}} -> {:ok, nil}
      {:stat, {:error, reason}} -> {:error, reason}
      {:metadata, {:error, reason}} -> {:error, reason}
      {:target, {:error, reason}} -> {:error, reason}
    end
  end

  def read(%Firewall{} = desired) do
    Helpers.read_firewall(desired, &read/1)
  end

  def read(%Proxy{} = desired) do
    read_proxy(desired, %{})
  end

  def read(%Mise{} = desired) do
    HostKit.Mise.read(desired, %{opts: []})
  end

  def read(%Package{} = desired) do
    HostKit.Package.read(desired, %{opts: []})
  end

  def read(%Command{} = desired), do: Helpers.read_run_resource(desired, [])

  def read(%Shell{} = desired), do: Helpers.read_run_resource(desired, [])

  def read(%Source{} = desired), do: HostKit.Source.Git.read(desired, [])

  def read(%Readiness{} = desired), do: read_readiness(desired, [])

  def read(%HostKit.Instance{} = desired), do: HostKit.Instance.Backend.read(desired, [])

  def read(%Systemd.Service{name: name} = desired) do
    read_systemd_unit("/etc/systemd/system/#{name}", desired)
  end

  def read(%Systemd.Timer{name: name} = desired) do
    read_systemd_unit("/etc/systemd/system/#{name}", desired)
  end

  def read(_resource), do: {:ok, nil}

  @spec read(struct(), map()) :: {:ok, struct() | nil} | {:error, term()}
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
      nil -> {:ok, nil}
      dir -> read_caddy_site(Path.join(dir, Helpers.caddy_site_filename(desired)), desired)
    end
  end

  def read(%Directory{path: path} = desired, context) do
    case stat_metadata(path, context) do
      {:ok, %{type: :directory} = metadata} ->
        {:ok,
         %Directory{desired | owner: metadata.owner, group: metadata.group, mode: metadata.mode}}

      {:ok, %{type: type}} ->
        {:error, {:not_directory, path, type}}

      {:error, :enoent} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def read(%File{path: path} = desired, context) do
    with {:metadata, {:ok, %{type: :regular} = metadata}} <-
           {:metadata, stat_metadata(path, context)},
         {:content, {:ok, content}} <- {:content, read_file(path, context)} do
      {:ok,
       %File{
         desired
         | content: content,
           owner: metadata.owner,
           group: metadata.group,
           mode: metadata.mode
       }}
    else
      {:metadata, {:ok, %{type: type}}} -> {:error, {:not_file, path, type}}
      {:metadata, {:error, :enoent}} -> {:ok, nil}
      {:metadata, {:error, reason}} -> {:error, reason}
      {:content, {:error, reason}} -> {:error, reason}
    end
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

  def read(resource, _context), do: read(resource)

  defp read_readiness(desired, opts) do
    if HostKit.Readiness.current?(desired, opts), do: {:ok, desired}, else: {:ok, nil}
  end

  defp read_file(path, context) do
    case Elixir.File.read(path) do
      {:error, :eacces} -> sudo_read_file(path, context)
      result -> result
    end
  end

  defp read_link(path, context) do
    case Elixir.File.read_link(path) do
      {:error, :eacces} -> sudo_read_link(path, context)
      result -> result
    end
  end

  defp sudo_read_file(path, %{opts: opts}) do
    if Keyword.get(opts, :sudo, false) do
      case System.cmd("sudo", ["cat", path], stderr_to_stdout: true) do
        {content, 0} -> {:ok, content}
        {output, status} -> {:error, {:sudo_cat_failed, status, output}}
      end
    else
      {:error, :eacces}
    end
  end

  defp sudo_read_file(_path, _context), do: {:error, :eacces}

  defp sudo_read_link(path, %{opts: opts}) do
    if Keyword.get(opts, :sudo, false) do
      case System.cmd("sudo", ["readlink", path], stderr_to_stdout: true) do
        {target, 0} -> {:ok, String.trim_trailing(target, "\n")}
        {output, status} -> {:error, {:sudo_readlink_failed, status, output}}
      end
    else
      {:error, :eacces}
    end
  end

  defp sudo_read_link(_path, _context), do: {:error, :eacces}

  defp read_proxy(%Proxy{path: path} = desired, context) do
    Helpers.read_content_resource(desired, path, &read_file(&1, context))
  end

  defp read_caddy_site(path, desired) do
    case Elixir.File.read(path) do
      {:ok, content} -> {:ok, %{desired | meta: Map.put(desired.meta, :content, content)}}
      {:error, :enoent} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stat_metadata(path), do: stat_metadata(path, %{})

  defp stat_metadata(path, context) do
    case stat_metadata_without_sudo(path) do
      {:error, :enoent} -> {:error, :enoent}
      {:error, _reason} -> sudo_stat_metadata(path, context)
      result -> result
    end
  end

  defp stat_metadata_without_sudo(path), do: stat_metadata_for_platform(path, [])

  defp sudo_stat_metadata(path, %{opts: opts}) do
    if Keyword.get(opts, :sudo, false) do
      stat_metadata_for_platform(path, ["sudo"])
    else
      {:error, :eacces}
    end
  end

  defp sudo_stat_metadata(_path, _context), do: {:error, :eacces}

  defp stat_metadata_for_platform(path, prefix) do
    case linux_stat_metadata(path, prefix) do
      {:error, {:stat_failed, _status, output}} = error ->
        if linux_stat_unsupported?(output), do: bsd_stat_metadata(path, prefix), else: error

      result ->
        result
    end
  end

  defp linux_stat_unsupported?(output),
    do: String.contains?(output, ["illegal option", "invalid option"])

  defp linux_stat_metadata(path, prefix) do
    case System.cmd(command(prefix, "stat"), args(prefix, ["-c", "%F:%U:%G:%a", path]),
           stderr_to_stdout: true
         ) do
      {output, 0} -> Helpers.parse_stat_output(output)
      {output, status} -> {:error, stat_error(status, output)}
    end
  end

  defp bsd_stat_metadata(path, prefix) do
    case System.cmd(command(prefix, "stat"), args(prefix, ["-f", "%HT:%Su:%Sg:%Lp", path]),
           stderr_to_stdout: true
         ) do
      {output, 0} -> Helpers.parse_stat_output(output)
      {output, status} -> {:error, stat_error(status, output)}
    end
  end

  defp stat_error(status, output) do
    if String.contains?(output, "No such file") do
      :enoent
    else
      {:stat_failed, status, output}
    end
  end

  defp command([command | _rest], _fallback), do: command
  defp command([], fallback), do: fallback

  defp args([_command | _rest], args), do: ["stat" | args]
  defp args([], args), do: args

  defp read_systemd_unit(path, desired) do
    case Elixir.File.read(path) do
      {:ok, content} ->
        {:ok,
         %{desired | meta: Map.put(desired.meta, :content, content)} |> Helpers.mark_render()}

      {:error, :enoent} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
