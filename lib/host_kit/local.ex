defmodule HostKit.Local do
  @moduledoc "Read-only inspection of resources on the local host."

  alias HostKit.Caddy
  alias HostKit.Resources.{Directory, File, User}
  alias HostKit.Systemd

  @spec read(struct()) :: {:ok, struct() | nil} | {:error, term()}
  def read(%User{name: name} = desired) do
    case System.cmd("getent", ["passwd", name], stderr_to_stdout: true) do
      {line, 0} -> {:ok, user_from_passwd(line, desired)}
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
      dir -> read_caddy_site(Path.join(dir, caddy_site_filename(desired)), desired)
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

  def read(resource, _context), do: read(resource)

  defp read_file(path, context) do
    case Elixir.File.read(path) do
      {:error, :eacces} -> sudo_read_file(path, context)
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

  defp read_caddy_site(path, desired) do
    case Elixir.File.read(path) do
      {:ok, content} -> {:ok, %{desired | meta: Map.put(desired.meta, :content, content)}}
      {:error, :enoent} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp caddy_site_filename(%Caddy.Site{meta: %{path: path}}), do: path
  defp caddy_site_filename(%Caddy.Site{name: name}), do: "#{name}.caddy"

  defp stat_metadata(path), do: stat_metadata(path, %{})

  defp stat_metadata(path, context) do
    case stat_metadata_without_sudo(path) do
      {:error, :enoent} -> {:error, :enoent}
      {:error, _reason} -> sudo_stat_metadata(path, context)
      result -> result
    end
  end

  defp stat_metadata_without_sudo(path) do
    with {:error, _reason} <- linux_stat_metadata(path, []) do
      bsd_stat_metadata(path, [])
    end
  end

  defp sudo_stat_metadata(path, %{opts: opts}) do
    if Keyword.get(opts, :sudo, false) do
      with {:error, _reason} <- linux_stat_metadata(path, ["sudo"]) do
        bsd_stat_metadata(path, ["sudo"])
      end
    else
      {:error, :eacces}
    end
  end

  defp sudo_stat_metadata(_path, _context), do: {:error, :eacces}

  defp linux_stat_metadata(path, prefix) do
    case System.cmd(command(prefix, "stat"), args(prefix, ["-c", "%F:%U:%G:%a", path]),
           stderr_to_stdout: true
         ) do
      {output, 0} -> parse_stat_output(output)
      {output, status} -> {:error, stat_error(status, output)}
    end
  end

  defp bsd_stat_metadata(path, prefix) do
    case System.cmd(command(prefix, "stat"), args(prefix, ["-f", "%HT:%Su:%Sg:%Lp", path]),
           stderr_to_stdout: true
         ) do
      {output, 0} -> parse_stat_output(output)
      {output, status} -> {:error, stat_error(status, output)}
    end
  end

  defp stat_error(status, output) do
    if String.contains?(output, ["No such file", "cannot stat"]) do
      :enoent
    else
      {:stat_failed, status, output}
    end
  end

  defp command([command | _rest], _fallback), do: command
  defp command([], fallback), do: fallback

  defp args([_command | _rest], args), do: ["stat" | args]
  defp args([], args), do: args

  defp parse_stat_output(output) do
    case output |> String.trim() |> String.split(":", parts: 4) do
      [type, owner, group, mode] ->
        {:ok,
         %{
           type: normalize_type(type),
           owner: owner,
           group: group,
           mode: String.to_integer(mode, 8)
         }}

      fields ->
        {:error, {:unexpected_stat_output, fields}}
    end
  end

  defp normalize_type(type) when type in ["directory", "Directory"], do: :directory
  defp normalize_type(type) when type in ["regular file", "Regular File"], do: :regular
  defp normalize_type(type), do: type

  defp user_from_passwd(line, %User{} = desired) do
    [_name, _password, _uid, _gid, _gecos, home, shell] =
      line
      |> String.trim()
      |> String.split(":", parts: 7)

    %User{desired | home: home, shell: shell}
  end

  defp read_systemd_unit(path, desired) do
    case Elixir.File.read(path) do
      {:ok, content} ->
        {:ok, %{desired | meta: Map.put(desired.meta, :content, content)} |> mark_render()}

      {:error, :enoent} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp mark_render(%Systemd.Service{} = actual) do
    Map.update!(actual, :meta, &Map.put(&1, :desired_render, Systemd.Service.render(actual)))
  end

  defp mark_render(%Systemd.Timer{} = actual) do
    Map.update!(actual, :meta, &Map.put(&1, :desired_render, Systemd.Timer.render(actual)))
  end
end
