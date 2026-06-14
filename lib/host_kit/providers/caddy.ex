defmodule HostKit.Providers.Caddy do
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
  def dsl_modules, do: [HostKit.Providers.Caddy.DSL]

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

    file_opts = Keyword.put(opts, :runner, Ops.runner(opts))

    with {:ok, content} <- rendered_content(site, render_site(site), opts),
         :ok <- HostKit.Runner.Files.mkdir_p(Path.dirname(path), file_opts),
         :ok <- HostKit.Runner.Files.write_file(path, content, file_opts),
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

  @impl true
  def validate(%Site{host: host, directives: directives}, _context) do
    cond do
      !is_binary(host) or host == "" -> {:error, :missing_host}
      directives == [] -> {:error, :missing_directives}
      true -> :ok
    end
  end

  def validate(_resource, _context), do: :ignore

  @spec render_site(Site.t()) :: iodata()
  def render_site(%Site{} = site) do
    [site.host, " {\n", Enum.map(site.directives, &render_directive/1), "}\n"]
  end

  defp rendered_content(%{meta: %{content: %HostKit.BackupRef{path: path}}}, _default, opts),
    do: HostKit.Runner.read_file(path, Keyword.put(opts, :runner, Ops.runner(opts)))

  defp rendered_content(_site, default, _opts), do: {:ok, IO.iodata_to_binary(default)}

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
