defmodule HostKit.DSL.Scope do
  @moduledoc false

  alias HostKit.{Conventions, Host, Project, ProviderConfig, Service, Storage}

  @project_key {__MODULE__, :project}
  @host_key {__MODULE__, :host}
  @service_key {__MODULE__, :service}
  @provider_config_key {__MODULE__, :provider_config}
  @observability_key {__MODULE__, :observability}
  @firewall_key {__MODULE__, :firewall}

  def start_project(name, opts) do
    Process.put(@project_key, Project.new(name, opts))
  end

  def finish_project do
    Process.delete(@project_key) || raise "no HostKit project in scope"
  end

  def start_observability do
    scope = if Process.get(@service_key), do: :service, else: :project
    Process.put(@observability_key, scope)
  end

  def finish_observability do
    Process.delete(@observability_key) || raise "no HostKit observability in scope"
  end

  def observability_active?, do: Process.get(@observability_key) != nil

  def put_observability(kind, value) do
    case Process.get(@observability_key) do
      :project -> update_project(&put_observability_value(&1, kind, value))
      :service -> update_current(:service, &put_observability_value(&1, kind, value))
      nil -> raise "no HostKit observability in scope"
    end
  end

  def start_firewall(opts \\ []) do
    scope = if Process.get(@host_key), do: :host, else: :project

    Process.put(@firewall_key, %HostKit.Firewall{
      scope: scope,
      path: Keyword.get(opts, :path, "/etc/nftables.d/hostkit.nft")
    })
  end

  def finish_firewall do
    firewall = Process.delete(@firewall_key) || raise "no HostKit firewall in scope"

    case firewall.scope do
      :project -> update_project(&put_firewall_value(&1, firewall))
      :host -> update_current(:host, &put_firewall_value(&1, firewall))
    end
  end

  def add_firewall_rule(rule) do
    firewall = Process.get(@firewall_key) || raise "no HostKit firewall in scope"
    Process.put(@firewall_key, %{firewall | rules: firewall.rules ++ [rule]})
    :ok
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
    prefixed(:user, service_path_name())
  end

  def unit_name(suffix \\ ".service") do
    prefixed(:unit, service_path_name()) <> suffix
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

  def put_listener(name, opts) do
    listener = HostKit.Listener.new(name, opts)

    update_current(:service, fn service ->
      listeners = service.meta |> Map.get(:listeners, %{}) |> Map.put(name, listener)
      %{service | meta: Map.put(service.meta, :listeners, listeners)}
    end)

    listener
  end

  def listener(name) do
    service = Process.get(@service_key) || raise "no HostKit service in scope"
    service.meta |> Map.get(:listeners, %{}) |> Map.fetch!(name)
  end

  def listener_upstream(name), do: name |> listener() |> HostKit.Listener.upstream()

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

  def update_last_resource(fun) do
    service = Process.get(@service_key) || raise "resources must be declared inside service/2"

    case service.resources do
      [] ->
        raise "no HostKit resource in scope"

      resources ->
        {last, rest_reversed} = resources |> Enum.reverse() |> List.pop_at(0)

        Process.put(@service_key, %{
          service
          | resources: Enum.reverse(rest_reversed, [fun.(last)])
        })

        :ok
    end
  end

  defp put_observability_value(%{meta: meta} = parent, kind, value) do
    observability = meta |> Map.get(:observability, %{}) |> Map.put(kind, value)
    %{parent | meta: Map.put(meta, :observability, observability)}
  end

  defp put_firewall_value(%{meta: meta} = parent, firewall) do
    %{parent | meta: Map.put(meta, :firewall, firewall)}
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
