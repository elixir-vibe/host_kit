defmodule HostKit.Providers.Caddy do
  @moduledoc "Caddy provider. Prefer this module over `HostKit.Plugins.Caddy`."

  @behaviour HostKit.Provider

  @impl true
  defdelegate provider_name, to: HostKit.Plugins.Caddy

  @impl true
  defdelegate dsl_modules, to: HostKit.Plugins.Caddy

  @impl true
  defdelegate resource_types, to: HostKit.Plugins.Caddy

  @impl true
  defdelegate render(resource, context), to: HostKit.Plugins.Caddy

  @impl true
  defdelegate validate(resource, context), to: HostKit.Plugins.Caddy

  defdelegate render_json_site(site), to: HostKit.Plugins.Caddy
  defdelegate render_site(site), to: HostKit.Plugins.Caddy
end
