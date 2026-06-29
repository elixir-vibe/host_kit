defmodule HostKit.Providers.Caddy.Scope do
  @moduledoc "Process-local scope helpers for Caddy provider DSL blocks."

  use DSL

  alias HostKit.Caddy.Directive.{Encode, FileServer, ReverseProxy, Root}
  alias HostKit.Caddy.Site

  scope(:site)

  def start_site(name, host, opts) do
    meta = opts |> Keyword.take([:path]) |> Map.new()
    push_site(%Site{name: name, host: host, meta: meta})
  end

  def add_root(path, opts) when is_binary(path) do
    update_site(
      &append_directive(&1, %Root{path: path, matcher: Keyword.get(opts, :matcher, "*")})
    )
  end

  def add_encode(formats) when is_list(formats) do
    update_site(&append_directive(&1, %Encode{formats: formats}))
  end

  def add_file_server(opts) do
    update_site(&append_directive(&1, %FileServer{browse: Keyword.get(opts, :browse, false)}))
  end

  def add_reverse_proxy(%HostKit.Endpoint{} = upstream) do
    update_site(&append_directive(&1, %ReverseProxy{upstreams: [upstream]}))
  end

  def add_reverse_proxy(upstream) when is_atom(upstream) do
    add_reverse_proxy(HostKit.DSL.Scope.listener_upstream(upstream))
  end

  def add_reverse_proxy(upstream) when is_binary(upstream) do
    update_site(&append_directive(&1, %ReverseProxy{upstreams: [upstream]}))
  end

  def add_reverse_proxy(upstreams) when is_list(upstreams) do
    update_site(&append_directive(&1, %ReverseProxy{upstreams: upstreams}))
  end

  def finish_site do
    pop_site()
  end

  def active?, do: site_active?()

  def put_monitor(type, opts) do
    update_site(fn site ->
      check =
        HostKit.Monitor.check(type, Keyword.put(opts, :resource_id, HostKit.Resource.id(site)))

      update_in(site.meta[:monitor], &(List.wrap(&1) ++ [check]))
    end)
  end

  def put_telemetry(config) do
    update_site(&put_in(&1.meta[:telemetry], config))
  end

  def put_logs(config) do
    update_site(&put_in(&1.meta[:logs], config))
  end

  defp append_directive(%Site{} = site, defdirective) do
    %{site | directives: site.directives ++ [defdirective]}
  end
end
