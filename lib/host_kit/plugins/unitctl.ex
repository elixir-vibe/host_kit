defmodule HostKit.Plugins.Unitctl do
  @moduledoc "Core HostKit plugin for transient process runtime primitives."

  @behaviour HostKit.Plugin

  @impl true
  def dsl_modules, do: []

  @impl true
  def resource_types, do: []
end
