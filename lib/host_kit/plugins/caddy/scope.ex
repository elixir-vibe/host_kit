defmodule HostKit.Plugins.Caddy.Scope do
  @moduledoc false

  alias HostKit.Caddy.Directive.{Encode, ReverseProxy}
  alias HostKit.Caddy.Site

  @key {__MODULE__, :site}

  def start_site(name, host) do
    Process.put(@key, %Site{name: name, host: host})
  end

  def add_encode(formats) when is_list(formats) do
    update_site(&append_directive(&1, %Encode{formats: formats}))
  end

  def add_reverse_proxy(upstream) when is_binary(upstream) do
    update_site(&append_directive(&1, %ReverseProxy{upstreams: [upstream]}))
  end

  def add_reverse_proxy(upstreams) when is_list(upstreams) do
    update_site(&append_directive(&1, %ReverseProxy{upstreams: upstreams}))
  end

  def finish_site do
    Process.delete(@key) || raise "no caddy site in scope"
  end

  defp append_directive(%Site{} = site, directive) do
    %{site | directives: site.directives ++ [directive]}
  end

  defp update_site(fun) do
    site = Process.get(@key) || raise "no caddy site in scope"
    Process.put(@key, fun.(site))
    :ok
  end
end
