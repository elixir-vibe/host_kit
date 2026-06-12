defmodule HostKit.DSL.Scope do
  @moduledoc false

  alias HostKit.{Host, Project, ProviderConfig, Service}

  @project_key {__MODULE__, :project}
  @host_key {__MODULE__, :host}
  @service_key {__MODULE__, :service}
  @provider_config_key {__MODULE__, :provider_config}

  def start_project(name, opts) do
    Process.put(@project_key, Project.new(name, opts))
  end

  def finish_project do
    Process.delete(@project_key) || raise "no HostKit project in scope"
  end

  def put_providers(providers) do
    update_project(&Project.put_providers(&1, providers))
  end

  def start_provider_config(name, module) do
    Process.put(@provider_config_key, %ProviderConfig{name: name, module: module})
  end

  def put_provider_config(key, value) do
    config = Process.get(@provider_config_key) || raise "no HostKit provider config in scope"
    Process.put(@provider_config_key, %{config | config: Map.put(config.config, key, value)})
    :ok
  end

  def finish_provider_config do
    config = Process.delete(@provider_config_key) || raise "no HostKit provider config in scope"
    update_project(&Project.put_provider_config(&1, config))
  end

  def start_host(name, opts) do
    Process.put(@host_key, %Host{
      name: name,
      hostname: Keyword.get(opts, :hostname),
      user: Keyword.get(opts, :user),
      sudo: Keyword.get(opts, :sudo, true),
      meta: Keyword.get(opts, :meta, %{})
    })
  end

  def finish_host do
    host = Process.delete(@host_key) || raise "no HostKit host in scope"
    update_project(&Project.add_host(&1, host))
  end

  def start_service(name, opts) do
    Process.put(@service_key, Service.new(name, opts))
  end

  def finish_service do
    service = Process.delete(@service_key) || raise "no HostKit service in scope"
    update_project(&Project.add_service(&1, service))
  end

  def update_current(:host, fun) do
    host = Process.get(@host_key) || raise "no HostKit host in scope"
    Process.put(@host_key, fun.(host))
    :ok
  end

  def add_resource(resource) do
    service = Process.get(@service_key) || raise "resources must be declared inside service/2"
    Process.put(@service_key, Service.add_resource(service, resource))
    :ok
  end

  defp update_project(fun) do
    project = Process.get(@project_key) || raise "no HostKit project in scope"
    Process.put(@project_key, fun.(project))
    :ok
  end
end
