defmodule HostKit.Runtime.Spec do
  @moduledoc "HostKit alias for Unitctl transient service specs."

  @type t :: Unitctl.Spec.t()

  @doc "Builds a runtime spec from a map or keyword list."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  defdelegate new(attrs), to: Unitctl.Spec

  @doc "Builds a runtime spec or raises `ArgumentError`."
  @spec new!(map() | keyword()) :: t()
  defdelegate new!(attrs), to: Unitctl.Spec

  @doc "Returns the transient systemd service unit name."
  @spec unit_name(t()) :: String.t()
  defdelegate unit_name(spec), to: Unitctl.Spec

  @doc "Converts the spec to systemdkit transient-unit properties."
  @spec to_properties(t()) :: [Systemd.TransientUnit.Property.t()]
  defdelegate to_properties(spec), to: Unitctl.Spec
end
