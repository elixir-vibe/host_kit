defmodule HostKit.TestPlugin do
  @moduledoc false

  @behaviour HostKit.Provider

  @impl true
  def provider_name, do: :test

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
