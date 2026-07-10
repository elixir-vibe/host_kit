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
  def read(%Site{} = site, context) do
    case Map.get(provider_config(context), :sites_dir) do
      nil ->
        {:ok, nil}

      sites_dir ->
        read_site(Path.join(sites_dir, Helpers.caddy_site_filename(site)), site, context)
    end
  end

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

    owner = Map.get(config, :owner)
    group = Map.get(config, :group)
    mode = Map.get(config, :mode, 0o644)

    file_opts =
      opts
      |> Keyword.put(:runner, Ops.runner(opts))
      |> Keyword.merge(owner: owner, group: group, mode: mode)

    with {:ok, content} <- rendered_content(site, render_site(site), opts),
         :ok <- HostKit.Runner.Files.mkdir_p(Path.dirname(path), file_opts),
         :ok <- HostKit.Runner.Files.write_file(path, content, file_opts),
         :ok <- Ops.chown(path, owner, group, opts),
         :ok <- Ops.chmod(path, mode, opts) do
      activate_site(site, config)
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

  defp read_site(path, site, context) do
    case HostKit.Runner.Files.read_file(path, Map.get(context, :opts, [])) do
      {:ok, content} -> {:ok, %{site | meta: Map.put(site.meta, :content, content)}}
      {:error, :enoent} -> {:ok, nil}
      {:error, {:command_failed, _command, _args, _status, output}} -> read_error(output)
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_error(output) do
    if String.contains?(output, ["No such file", "not found"]),
      do: {:ok, nil},
      else: {:error, {:caddy_site_read_failed, output}}
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

  defp activate_site(%Site{} = site, config) do
    if activate?(config) do
      admin_url = Map.get(config, :admin_url, "http://127.0.0.1:2019")
      route = site |> HostKit.Caddy.JSON.route_for_site() |> HostKit.Caddy.JSON.to_map()

      with {:ok, routes, etag} <- fetch_routes(admin_url) do
        put_route(admin_url, routes, etag, site.host, route)
      end
    else
      :ok
    end
  end

  defp activate?(config) do
    Map.get(config, :activate, default_activate?(config))
  end

  defp default_activate?(config) do
    Map.get(config, :sites_dir) == "/etc/caddy/sites"
  end

  defp fetch_routes(admin_url) do
    url = admin_url <> "/config/apps/http/servers/srv0/routes"

    case Req.get(url, retry: false, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: 200, body: routes, headers: headers}} when is_list(routes) ->
        {:ok, routes, List.first(headers["etag"] || [])}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:caddy_admin_fetch_routes_failed, status, body}}

      {:error, reason} ->
        {:error, {:caddy_admin_request_failed, url, reason}}
    end
  end

  defp put_route(admin_url, routes, etag, host, route) do
    headers = [{"content-type", "application/json"}]
    headers = if etag, do: [{"if-match", etag} | headers], else: headers

    case Enum.find_index(routes, &route_matches_host?(&1, host)) do
      nil ->
        request(:post, admin_url <> "/config/apps/http/servers/srv0/routes", route, headers)

      index ->
        request(
          :patch,
          admin_url <> "/config/apps/http/servers/srv0/routes/#{index}",
          route,
          headers
        )
    end
  end

  defp request(method, url, json, headers) do
    case Req.request(
           method: method,
           url: url,
           json: json,
           headers: headers,
           retry: false,
           receive_timeout: 5_000
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:caddy_admin_update_route_failed, status, body}}

      {:error, reason} ->
        {:error, {:caddy_admin_request_failed, url, reason}}
    end
  end

  defp route_matches_host?(%{"match" => matches}, host) when is_list(matches) do
    Enum.any?(matches, fn
      %{"host" => hosts} when is_list(hosts) -> host in hosts
      _other -> false
    end)
  end

  defp route_matches_host?(_route, _host), do: false

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
