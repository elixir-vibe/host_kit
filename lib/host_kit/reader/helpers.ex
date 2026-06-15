defmodule HostKit.Reader.Helpers do
  @moduledoc false

  def read_run_resource(desired, opts) do
    if HostKit.RunStamp.current?(desired, opts), do: {:ok, desired}, else: {:ok, nil}
  end

  alias HostKit.Caddy
  alias HostKit.Resources.{Account, Directory, File, Symlink}
  alias HostKit.Systemd

  def read_directory(%Directory{path: path} = desired, stat_fun) do
    case stat_fun.(path) do
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

  def read_firewall(%HostKit.Firewall{path: path} = desired, read_fun) do
    case read_fun.(%File{path: path, content: ""}) do
      {:ok, nil} -> {:ok, nil}
      {:ok, actual} -> {:ok, %{desired | meta: Map.put(desired.meta, :content, actual.content)}}
      {:error, reason} -> {:error, reason}
    end
  end

  def read_env_file(%HostKit.Resources.EnvFile{path: path} = desired, read_fun) do
    desired_file = %File{
      path: path,
      content: :redacted,
      owner: desired.owner,
      group: desired.group,
      mode: desired.mode
    }

    case read_fun.(desired_file) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, actual} ->
        {:ok,
         %HostKit.Resources.EnvFile{
           desired
           | owner: actual.owner,
             group: actual.group,
             mode: actual.mode,
             meta: put_env_file_public_entries(desired, actual.content)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def read_content_resource(desired, path, read_fun) do
    case read_fun.(path) do
      {:ok, content} -> {:ok, %{desired | meta: Map.put(desired.meta, :content, content)}}
      {:error, :enoent} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  def read_symlink(%Symlink{path: path} = desired, stat_fun, read_link_fun) do
    with {:metadata, {:ok, %{type: :symlink} = metadata}} <- {:metadata, stat_fun.(path)},
         {:target, {:ok, target}} <- {:target, read_link_fun.(path)} do
      {:ok, %Symlink{desired | to: target, owner: metadata.owner, group: metadata.group}}
    else
      {:metadata, {:ok, %{type: type}}} -> {:error, {:not_symlink, path, type}}
      {:metadata, {:error, :enoent}} -> {:ok, nil}
      {:metadata, {:error, reason}} -> {:error, reason}
      {:target, {:error, reason}} -> {:error, reason}
    end
  end

  def read_file(%File{path: path} = desired, stat_fun, read_fun) do
    with {:metadata, {:ok, %{type: :regular} = metadata}} <- {:metadata, stat_fun.(path)},
         {:content, {:ok, content}} <- {:content, read_fun.(path)} do
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

  defp put_env_file_public_entries(desired, content) do
    public_entries = HostKit.Env.public_entries(desired)

    case HostKit.Env.public_entries_from_content(content, Map.keys(public_entries)) do
      {:ok, actual_entries} ->
        desired.meta
        |> Map.put(:public_entries, public_entries)
        |> Map.put(:actual_public_entries, actual_entries)

      {:error, _reason} ->
        desired.meta
        |> Map.put(:public_entries, public_entries)
        |> Map.put(:actual_public_entries, :invalid)
    end
  end

  def parse_stat_output(output) do
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

  def caddy_site_filename(%Caddy.Site{meta: %{path: path}}), do: path
  def caddy_site_filename(%Caddy.Site{name: name}), do: "#{name}.caddy"

  def mark_render(%Systemd.Service{} = actual),
    do: Map.update!(actual, :meta, &Map.put(&1, :desired_render, Systemd.Service.render(actual)))

  def mark_render(%Systemd.Timer{} = actual),
    do: Map.update!(actual, :meta, &Map.put(&1, :desired_render, Systemd.Timer.render(actual)))

  def account_from_passwd(line, %Account{} = desired) do
    [_name, _password, _uid, _gid, _gecos, home, shell] =
      line |> String.trim() |> String.split(":", parts: 7)

    %Account{desired | home: home, shell: shell}
  end

  defp normalize_type(type) when type in ["directory", "Directory"], do: :directory
  defp normalize_type(type) when type in ["regular file", "Regular File"], do: :regular
  defp normalize_type(type) when type in ["symbolic link", "Symbolic Link"], do: :symlink
  defp normalize_type(type), do: type
end
