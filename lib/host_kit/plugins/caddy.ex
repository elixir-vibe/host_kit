defmodule HostKit.Plugins.Caddy do
  @moduledoc "Caddy provider for HostKit."

  @behaviour HostKit.Provider

  alias HostKit.Caddy.Directive.{Encode, ReverseProxy}
  alias HostKit.Caddy.Site

  @impl true
  def provider_name, do: :caddy

  @impl true
  def dsl_modules, do: [HostKit.Plugins.Caddy.DSL]

  @impl true
  def resource_types, do: [Site]

  @impl true
  def render(%Site{} = site, _context) do
    {:ok, render_site(site)}
  end

  @spec render_site(Site.t()) :: iodata()

  def render(_resource, _context), do: :ignore

  @impl true
  def validate(%Site{host: host, directives: directives}, _context) do
    cond do
      !is_binary(host) or host == "" -> {:error, :missing_host}
      directives == [] -> {:error, :missing_directives}
      true -> :ok
    end
  end

  def validate(_resource, _context), do: :ignore

  def render_site(%Site{} = site) do
    [site.host, " {\n", Enum.map(site.directives, &render_directive/1), "}\n"]
  end

  defp render_directive(%Encode{formats: formats}) do
    ["\tencode", Enum.map(formats, &[" ", to_string(&1)]), "\n"]
  end

  defp render_directive(%ReverseProxy{upstreams: upstreams}) do
    ["\treverse_proxy", Enum.map(upstreams, &[" ", &1]), "\n"]
  end
end
