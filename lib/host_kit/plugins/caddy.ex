defmodule HostKit.Plugins.Caddy do
  @moduledoc "Caddy provider for HostKit."

  @behaviour HostKit.Provider

  alias HostKit.Caddy.Directive.{Encode, FileServer, ReverseProxy, Root}
  alias HostKit.Caddy.Site
  alias HostKit.Change
  alias HostKit.Reader.Helpers
  alias HostKit.Runner.Ops

  @impl true
  def provider_name, do: :caddy

  @impl true
  def dsl_modules, do: [HostKit.Plugins.Caddy.DSL]

  @impl true
  def resource_types, do: [Site]

  @impl true
  def apply(%Change{action: action, after: %Site{} = site}, context)
      when action in [:create, :update] do
    config = provider_config(context)

    path =
      Path.join(
        Map.get(config, :sites_dir, "/etc/caddy/sites"),
        Helpers.caddy_site_filename(site)
      )

    opts = Map.get(context, :opts, [])

    with :ok <- HostKit.Runner.mkdir_p(Ops.runner(opts), Path.dirname(path), opts),
         :ok <- HostKit.Runner.write_file(Ops.runner(opts), path, render_site(site), opts),
         :ok <- Ops.chown(path, Map.get(config, :owner), Map.get(config, :group), opts) do
      Ops.chmod(path, Map.get(config, :mode, 0o644), opts)
    end
  end

  def apply(_change, _context), do: :ignore

  @impl true
  def render(%Site{} = site, _context) do
    {:ok, render_json_site(site)}
  end

  def render(_resource, _context), do: :ignore

  @spec render_json_site(Site.t()) :: String.t()
  def render_json_site(%Site{} = site) do
    site
    |> HostKit.Caddy.JSON.route_for_site()
    |> HostKit.Caddy.JSON.encode!()
  end

  @spec render_site(Site.t()) :: iodata()

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

  defp provider_config(%{project: project}) do
    project.provider_configs
    |> Map.get(:caddy)
    |> case do
      nil -> %{}
      config -> config.config
    end
  end

  defp provider_config(_context), do: %{}

  defp render_directive(%Root{matcher: matcher, path: path}) do
    ["\troot ", matcher, " ", path, "\n"]
  end

  defp render_directive(%Encode{formats: formats}) do
    ["\tencode", Enum.map(formats, &[" ", to_string(&1)]), "\n"]
  end

  defp render_directive(%FileServer{browse: false}), do: "\tfile_server\n"
  defp render_directive(%FileServer{browse: true}), do: "\tfile_server browse\n"

  defp render_directive(%ReverseProxy{upstreams: upstreams}) do
    ["\treverse_proxy", Enum.map(upstreams, &[" ", &1]), "\n"]
  end
end
