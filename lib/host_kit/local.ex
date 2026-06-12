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
         {:content, {:ok, content}} <- {:content, Elixir.File.read(path)} do
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
    read_systemd_unit("/etc/systemd/system/#{name}", desired, &Systemd.Service.render/1)
  end

  def read(%Systemd.Timer{name: name} = desired) do
    read_systemd_unit("/etc/systemd/system/#{name}", desired, &Systemd.Timer.render/1)
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

  def read(resource, _context), do: read(resource)

  defp read_caddy_site(path, desired) do
    case Elixir.File.read(path) do
      {:ok, content} -> {:ok, %{desired | meta: Map.put(desired.meta, :content, content)}}
      {:error, :enoent} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp caddy_site_filename(%Caddy.Site{meta: %{path: path}}), do: path
  defp caddy_site_filename(%Caddy.Site{name: name}), do: "#{name}.caddy"

  defp stat_metadata(path) do
    with {:error, _reason} <- linux_stat_metadata(path) do
      bsd_stat_metadata(path)
    end
  end

  defp linux_stat_metadata(path) do
    case System.cmd("stat", ["-c", "%U:%G:%a", path], stderr_to_stdout: true) do
      {output, 0} -> parse_stat_output(output)
      {output, status} -> {:error, {:stat_failed, status, output}}
    end
  end

  defp bsd_stat_metadata(path) do
    case System.cmd("stat", ["-f", "%Su:%Sg:%Lp", path], stderr_to_stdout: true) do
      {output, 0} -> parse_stat_output(output)
      {output, status} -> {:error, {:stat_failed, status, output}}
    end
  end

  defp parse_stat_output(output) do
    case output |> String.trim() |> String.split(":", parts: 3) do
      [owner, group, mode] ->
        {:ok, %{owner: owner, group: group, mode: String.to_integer(mode, 8)}}

      fields ->
        {:error, {:unexpected_stat_output, fields}}
    end
  end

  defp user_from_passwd(line, %User{} = desired) do
    [_name, _password, _uid, _gid, _gecos, home, shell] =
      line
      |> String.trim()
      |> String.split(":", parts: 7)

    %User{desired | home: home, shell: shell}
  end

  defp read_systemd_unit(path, desired, render) do
    case Elixir.File.read(path) do
      {:ok, content} ->
        {:ok,
         %{
           desired
           | meta: Map.put(desired.meta, :content, content),
             unit: desired.unit,
             service: desired.service,
             install: desired.install
         }
         |> mark_render(render)}

      {:error, :enoent} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp mark_render(actual, render) do
    Map.update!(actual, :meta, &Map.put(&1, :desired_render, render.(actual)))
  end
end
