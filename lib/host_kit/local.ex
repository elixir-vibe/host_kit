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
    case Elixir.File.stat(path) do
      {:ok, %Elixir.File.Stat{type: :directory, mode: mode}} ->
        {:ok, %Directory{desired | mode: desired.mode || mode}}

      {:ok, %Elixir.File.Stat{type: type}} ->
        {:error, {:not_directory, path, type}}

      {:error, :enoent} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def read(%File{path: path} = desired) do
    with {:stat, {:ok, %Elixir.File.Stat{type: :regular, mode: mode}}} <-
           {:stat, Elixir.File.stat(path)},
         {:content, {:ok, content}} <- {:content, Elixir.File.read(path)} do
      {:ok, %File{desired | content: content, mode: desired.mode || mode}}
    else
      {:stat, {:ok, %Elixir.File.Stat{type: type}}} -> {:error, {:not_file, path, type}}
      {:stat, {:error, :enoent}} -> {:ok, nil}
      {:stat, {:error, reason}} -> {:error, reason}
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
