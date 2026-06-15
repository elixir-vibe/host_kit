defmodule HostKit.Naming do
  @moduledoc "Shared naming and path/identity normalization helpers."

  @spec path_segment(atom() | String.t()) :: String.t()
  def path_segment(value), do: to_string(value)

  @spec identity_segment(atom() | String.t()) :: String.t()
  def identity_segment(value) do
    value
    |> to_string()
    |> String.replace("_", "-")
  end

  @spec identity_path(atom() | String.t()) :: String.t()
  def identity_path(value) do
    value
    |> identity_segment()
    |> String.replace("/", "-")
  end

  @spec workspace_path(atom() | String.t(), atom() | String.t(), atom() | String.t()) ::
          String.t()
  def workspace_path(owner, workspace_path, service_path) do
    Path.join([path_segment(owner), path_segment(workspace_path), path_segment(service_path)])
  end

  @spec workspace_identity(atom() | String.t(), atom() | String.t(), atom() | String.t()) ::
          String.t()
  def workspace_identity(owner, workspace_path, service_path) do
    [owner, workspace_path, service_path]
    |> Enum.map_join("-", &path_segment/1)
    |> String.replace("/", "-")
    |> identity_segment()
  end
end
