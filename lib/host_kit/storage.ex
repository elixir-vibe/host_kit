defmodule HostKit.Storage do
  @moduledoc "Helpers for named storage volumes."

  alias HostKit.Resources.Directory
  alias HostKit.Storage.Volume

  @spec volume(atom(), keyword()) :: Volume.t()
  def volume(name, opts) when is_atom(name) do
    opts
    |> Keyword.update(:mode, nil, &HostKit.Mode.normalize!/1)
    |> Keyword.put(:name, name)
    |> then(&struct!(Volume, &1))
  end

  @spec directory(Volume.t()) :: Directory.t()
  def directory(%Volume{} = volume) do
    %Directory{
      path: volume.path,
      owner: volume.owner,
      group: volume.group,
      mode: volume.mode,
      meta: %{storage: volume.name, backup: volume.backup, secret: volume.secret}
    }
  end

  @spec read_write_path(Volume.t()) :: String.t() | nil
  def read_write_path(%Volume{writable: true, path: path}), do: path
  def read_write_path(%Volume{writable: false}), do: nil

  @spec read_write_paths([Volume.t()]) :: [String.t()]
  def read_write_paths(volumes) do
    volumes
    |> Enum.map(&read_write_path/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec backup?(Volume.t()) :: boolean()
  def backup?(%Volume{backup: backup}), do: backup

  @spec secret?(Volume.t()) :: boolean()
  def secret?(%Volume{secret: secret}), do: secret

  @spec mount_path(Volume.t()) :: String.t()
  def mount_path(%Volume{mount_path: nil, path: path}), do: path
  def mount_path(%Volume{mount_path: mount_path}), do: mount_path
end
