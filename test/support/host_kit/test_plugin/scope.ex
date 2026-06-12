defmodule HostKit.TestPlugin.Scope do
  @moduledoc false

  @key {__MODULE__, :site}

  def start_site(host) do
    Process.put(@key, %HostKit.TestSite{host: host})
  end

  def put_upstream(upstream) do
    site = Process.get(@key) || raise "no test site in scope"
    Process.put(@key, %{site | upstream: upstream})
    :ok
  end

  def finish_site do
    Process.delete(@key) || raise "no test site in scope"
  end
end
