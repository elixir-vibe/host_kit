defmodule HostKit.Naming do
  @moduledoc "Shared naming and path/identity normalization helpers."

  @type name_part :: atom() | String.t() | integer()

  @spec path_segment(name_part()) :: String.t()
  def path_segment(value), do: to_string(value)

  @spec identity_segment(name_part()) :: String.t()
  def identity_segment(value) do
    value
    |> to_string()
    |> String.replace("_", "-")
  end

  @spec identity_path(name_part()) :: String.t()
  def identity_path(value) do
    value
    |> identity_segment()
    |> String.replace("/", "-")
  end

  @spec systemd_unit(name_part(), name_part()) :: String.t()
  def systemd_unit(identity, suffix \\ ".service") do
    identity = identity_segment(identity)

    if String.ends_with?(identity, [".service", ".timer"]) do
      identity
    else
      identity <> to_string(suffix)
    end
  end

  @spec service_user(name_part()) :: String.t()
  def service_user(identity), do: identity_segment(identity)

  @spec prefixed(name_part(), name_part()) :: String.t()
  def prefixed(prefix, identity), do: to_string(prefix) <> identity_segment(identity)

  @spec readiness([name_part()] | name_part(), [name_part()] | name_part()) :: String.t()
  def readiness(namespace, name) do
    resource(List.wrap(namespace) ++ List.wrap(name) ++ [:ready])
  end

  @spec resource([name_part()]) :: String.t()
  def resource(parts), do: Enum.map_join(parts, "_", &underscore_segment/1)

  @spec ingress_route(name_part(), String.t(), pos_integer()) :: String.t()
  def ingress_route(name, host, index) do
    resource([name, route_suffix(host), index])
  end

  @spec route_suffix(String.t()) :: String.t()
  def route_suffix(host) do
    host
    |> String.replace(~r/[^A-Za-z0-9_]+/, "_")
    |> String.trim("_")
  end

  @spec elixir_release(name_part()) :: String.t()
  def elixir_release(name), do: name |> identity_segment() |> String.replace("-", "_")

  @spec capability(atom() | String.t()) :: atom() | String.t()
  def capability(name) when is_atom(name), do: name

  def capability(name) when is_binary(name) do
    name
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> name
  end

  @spec workspace_path(name_part(), name_part(), name_part()) :: String.t()
  def workspace_path(owner, workspace_path, service_path) do
    Path.join([path_segment(owner), path_segment(workspace_path), path_segment(service_path)])
  end

  @spec workspace_identity(name_part(), name_part(), name_part()) :: String.t()
  def workspace_identity(owner, workspace_path, service_path) do
    [owner, workspace_path, service_path]
    |> Enum.map_join("-", &path_segment/1)
    |> String.replace("/", "-")
    |> identity_segment()
  end

  defp underscore_segment(value) do
    value
    |> path_segment()
    |> String.replace(~r/[^A-Za-z0-9_]+/, "_")
    |> String.trim("_")
  end
end
