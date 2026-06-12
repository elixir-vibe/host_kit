defmodule HostKit.DSL.Scope do
  @moduledoc false

  alias HostKit.{Conventions, Host, Project, ProviderConfig, Service, Storage}

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
    service = Service.new(name, opts)
    path_name = Keyword.get(opts, :path, Keyword.get(opts, :as, name))
    Process.put(@service_key, %{service | meta: Map.put(service.meta, :path_name, path_name)})
  end

  def finish_service do
    service = Process.delete(@service_key) || raise "no HostKit service in scope"
    update_project(&Project.add_service(&1, service))
  end

  def put_root(name, path), do: update_project(&Project.put_convention_root(&1, name, path))

  def put_prefix(name, prefix),
    do: update_project(&Project.put_convention_prefix(&1, name, prefix))

  def set_service_path_name(path_name) do
    update_current(:service, &put_in(&1.meta[:path_name], path_name))
  end

  def service_name do
    service = Process.get(@service_key) || raise "no HostKit service in scope"
    service.name
  end

  def service_path_name do
    service = Process.get(@service_key) || raise "no HostKit service in scope"
    Map.get(service.meta, :path_name, service.name)
  end

  def service_user do
    prefixed(:user, service_name())
  end

  def unit_name(suffix \\ ".service") do
    prefixed(:unit, service_name()) <> suffix
  end

  def root_path(root, child \\ nil) do
    base =
      Path.join(Conventions.root!(project_conventions(), root), to_string(service_path_name()))

    case child do
      nil -> base
      value -> Path.join(base, to_string(value))
    end
  end

  def prefixed(name, value), do: Conventions.prefixed(project_conventions(), name, value)

  def put_storage(name, opts) do
    volume = Storage.volume(name, storage_opts(opts))

    update_current(:service, fn service ->
      storage = service.meta |> Map.get(:storage, %{}) |> Map.put(name, volume)
      %{service | meta: Map.put(service.meta, :storage, storage)}
    end)

    add_resource(Storage.directory(volume))
    volume
  end

  def storage_volume(name) do
    service = Process.get(@service_key) || raise "no HostKit service in scope"
    service.meta |> Map.get(:storage, %{}) |> Map.fetch!(name)
  end

  def storage_path(name), do: storage_volume(name).path

  def writable_storage_paths do
    service = Process.get(@service_key) || raise "no HostKit service in scope"
    service.meta |> Map.get(:storage, %{}) |> Map.values() |> Storage.read_write_paths()
  end

  def backup_storage do
    service = Process.get(@service_key) || raise "no HostKit service in scope"

    service.meta
    |> Map.get(:storage, %{})
    |> Enum.filter(fn {_name, volume} -> Storage.backup?(volume) end)
    |> Enum.map(fn {_name, volume} -> volume end)
  end

  def update_current(:host, fun) do
    host = Process.get(@host_key) || raise "no HostKit host in scope"
    Process.put(@host_key, fun.(host))
    :ok
  end

  def update_current(:service, fun) do
    service = Process.get(@service_key) || raise "no HostKit service in scope"
    Process.put(@service_key, fun.(service))
    :ok
  end

  def add_resource(resource) do
    service = Process.get(@service_key) || raise "resources must be declared inside service/2"
    Process.put(@service_key, Service.add_resource(service, resource))
    :ok
  end

  defp storage_opts(opts) do
    opts = Keyword.put_new(opts, :owner, service_user())
    opts = Keyword.put_new(opts, :group, Keyword.fetch!(opts, :owner))

    case Keyword.pop(opts, :under) do
      {nil, opts} -> opts
      {root, opts} -> Keyword.put(opts, :path, root_path(root, Keyword.get(opts, :path)))
    end
  end

  defp project_conventions do
    project = Process.get(@project_key) || raise "no HostKit project in scope"
    project.conventions
  end

  defp update_project(fun) do
    project = Process.get(@project_key) || raise "no HostKit project in scope"
    Process.put(@project_key, fun.(project))
    :ok
  end
end
