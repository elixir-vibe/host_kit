defmodule HostKit.TestPlugin.Scope do
  @moduledoc "Process-local scope helpers for the HostKit test plugin DSL."

  use DSL

  scope(:site)

  def start_site(host) do
    push_site(%HostKit.TestSite{host: host})
  end

  def put_upstream(upstream) do
    update_site(&%{&1 | upstream: upstream})
  end

  def finish_site do
    pop_site()
  end
end
