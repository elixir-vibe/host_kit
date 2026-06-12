defmodule HostKit.TestPlugin do
  @moduledoc false

  @behaviour HostKit.Plugin

  @impl true
  def dsl_modules, do: [HostKit.TestPlugin.DSL]

  @impl true
  def resource_types, do: [HostKit.TestSite]

  @impl true
  def render(%HostKit.TestSite{} = site, _context) do
    {:ok, [site.host, " -> ", site.upstream, "\n"]}
  end

  def render(_resource, _context), do: :ignore
end
