defmodule HostKit.DSL.Scope do
  @moduledoc false

  alias HostKit.{Conventions, Host, Project, ProviderConfig, Service, Storage}

  @project_key {__MODULE__, :project}
  @host_key {__MODULE__, :host}
  @service_key {__MODULE__, :service}
  @workspace_key {__MODULE__, :workspace}
  @inside_key {__MODULE__, :inside}
  @provider_config_key {__MODULE__, :provider_config}
  @mise_key {__MODULE__, :mise}
  @ssh_key {__MODULE__, :ssh}
  @bootstrap_key {__MODULE__, :bootstrap}
  @observability_key {__MODULE__, :observability}
  @firewall_key {__MODULE__, :firewall}
  @proxy_key {__MODULE__, :proxy}
  @proxy_service_key {__MODULE__, :proxy_service}
  @default_providers_key {__MODULE__, :default_providers}

  def put_default_providers(providers) do
    Process.put(@default_providers_key, providers)
  end

  def start_project(name, opts) do
    Process.put(@project_key, Project.new(name, project_opts(opts)))
  end

  defp project_opts(opts) do
    if Keyword.has_key?(opts, :providers) do
      opts
    else
      Keyword.put(opts, :providers, Process.get(@default_providers_key, []))
    end
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

  def start_mise(opts) do
    opts = Keyword.put_new(opts, :path, "/usr/local/bin/mise")
    opts = Keyword.put_new(opts, :system_data_dir, "/usr/local/share/mise")
    Process.put(@mise_key, HostKit.Resources.Mise.new(opts))
  end

  def add_tool(name, version, opts) do
    mise = Process.get(@mise_key) || raise "no HostKit mise in scope"
    Process.put(@mise_key, HostKit.Resources.Mise.add_tool(mise, name, version, opts))
    :ok
  end

  def finish_mise do
    mise = Process.delete(@mise_key) || raise "no HostKit mise in scope"
    add_resource(mise)
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

  def put_tenant(name, opts) do
    update_project(&Project.add_tenant(&1, HostKit.Tenant.new(name, opts)))
  end

  def start_proxy(name, opts) do
    Process.put(@proxy_key, %HostKit.Proxy{
      name: name,
      provider: Keyword.fetch!(opts, :provider),
      path: Keyword.get(opts, :path, "/etc/gatehouse/config.exs"),
      meta: Keyword.get(opts, :meta, %{})
    })
  end

  def finish_proxy do
    proxy = Process.delete(@proxy_key) || raise "no HostKit proxy in scope"
    update_project(&Project.add_proxy(&1, proxy))
  end

  def proxy_active?, do: Process.get(@proxy_key) != nil
  def proxy_service_active?, do: Process.get(@proxy_service_key) != nil

  def put_proxy_state(path) do
    update_proxy(&%{&1 | state: path})
  end

  def put_proxy_listener(scheme, opts) when scheme in [:http, :https] do
    listener = %{scheme: scheme, opts: opts}
    update_proxy(&%{&1 | listeners: &1.listeners ++ [listener]})
  end

  def put_proxy_acme(opts) do
    update_proxy(&%{&1 | acme: opts})
  end

  def put_proxy_balance(policy, opts) do
    update_proxy_service(&%{&1 | balance: %{policy: policy, opts: opts}})
  end

  def put_proxy_health(path, opts) do
    update_proxy_service(&%{&1 | health: %{path: path, opts: opts}})
  end

  def put_proxy_drain(timeout) do
    update_proxy_service(&%{&1 | drain: timeout})
  end

  def put_proxy_tls(tls) do
    update_proxy_service(&%{&1 | tls: tls})
  end

  def start_proxy_service(name, opts) do
    Process.put(@proxy_service_key, HostKit.Proxy.service(name, opts))
  end

  def finish_proxy_service do
    service = Process.delete(@proxy_service_key) || raise "no HostKit proxy service in scope"
    proxy = Process.get(@proxy_key) || raise "no HostKit proxy in scope"
    Process.put(@proxy_key, %{proxy | services: proxy.services ++ [service]})
  end

  def add_proxy_host(host) do
    update_proxy_service(&%{&1 | hosts: &1.hosts ++ [host]})
  end

  def add_proxy_target(name, opts) do
    target =
      cond do
        Keyword.has_key?(opts, :safe_rpc) ->
          %{
            name: name,
            safe_rpc: Keyword.fetch!(opts, :safe_rpc),
            active: Keyword.get(opts, :active, false),
            metadata: Keyword.get(opts, :metadata, %{})
          }

        Keyword.has_key?(opts, :to) ->
          %{
            name: name,
            to: Keyword.fetch!(opts, :to),
            active: Keyword.get(opts, :active, false),
            metadata: Keyword.get(opts, :metadata, %{})
          }

        true ->
          %{
            name: name,
            url: Keyword.fetch!(opts, :url),
            active: Keyword.get(opts, :active, false),
            metadata: Keyword.get(opts, :metadata, %{})
          }
      end

    update_proxy_service(&%{&1 | targets: &1.targets ++ [target]})
  end

  def start_host(name, opts) do
    Process.put(@host_key, %Host{
      name: name,
      hostname: Keyword.fetch!(opts, :at),
      user: nil,
      sudo: false,
      meta: Keyword.get(opts, :meta, %{})
    })
  end

  def start_ssh(opts \\ []) do
    host = Process.get(@host_key) || raise "ssh/1 must be declared inside host/2"

    Process.put(@ssh_key, true)

    update_current(
      :host,
      &update_in(&1.meta[:ssh], fn existing -> Keyword.merge(existing || [], opts) end)
    )

    if user = Keyword.get(opts, :user), do: update_current(:host, &Map.put(&1, :user, user))

    if Keyword.has_key?(opts, :sudo),
      do: update_current(:host, &Map.put(&1, :sudo, Keyword.fetch!(opts, :sudo)))

    host
  end

  def finish_ssh do
    Process.delete(@ssh_key) || raise "no HostKit ssh in scope"
    :ok
  end

  def ssh_active?, do: Process.get(@ssh_key) == true

  def put_ssh(key, value) do
    update_current(:host, fn host ->
      host = if key == :user, do: %{host | user: value}, else: host
      host = if key == :sudo, do: %{host | sudo: value}, else: host
      update_in(host.meta[:ssh], &Keyword.put(&1 || [], key, value))
    end)
  end

  def start_bootstrap do
    Process.put(@bootstrap_key, true)
  end

  def finish_bootstrap do
    Process.delete(@bootstrap_key) || raise "no HostKit bootstrap in scope"
    :ok
  end

  def finish_host do
    host = Process.delete(@host_key) || raise "no HostKit host in scope"
    update_project(&Project.add_host(&1, host))
  end

  def start_service(name, opts) do
    service = Service.new(name, opts)
    base_name = Keyword.get(opts, :path, Keyword.get(opts, :as, name))
    path_name = service_path(base_name)
    identity_name = service_identity(base_name)

    meta =
      service.meta
      |> Map.put(:path_name, path_name)
      |> Map.put(:identity_name, identity_name)
      |> maybe_put_workspace()

    Process.put(@service_key, %{service | meta: meta})
  end

  def finish_service do
    service = Process.delete(@service_key) || raise "no HostKit service in scope"
    update_project(&Project.add_service(&1, service))
  end

  def start_workspace(name, opts) do
    workspace = %{
      name: name,
      owner: Keyword.get(opts, :owner, name),
      path_name: Keyword.get(opts, :path, name),
      identity: Keyword.get(opts, :identity)
    }

    Process.put(@workspace_key, workspace)
  end

  def finish_workspace do
    Process.delete(@workspace_key) || raise "no HostKit workspace in scope"
    :ok
  end

  def start_inside do
    Process.put(@inside_key, true)
  end

  def finish_inside do
    Process.delete(@inside_key) || raise "no HostKit inside scope"
    :ok
  end

  def inside_active?, do: Process.get(@inside_key) == true

  def add_inside_monitor(type, opts) do
    service =
      Process.get(@service_key) || raise "inside monitors must be declared inside service/2"

    check = HostKit.Monitor.check(type, opts)
    monitors = service.meta |> Map.get(:inside_monitor, []) |> Kernel.++([check])
    Process.put(@service_key, %{service | meta: Map.put(service.meta, :inside_monitor, monitors)})
    :ok
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
    prefixed(:user, service_identity_name())
  end

  def service_account do
    service = Process.get(@service_key) || raise "no HostKit service in scope"
    Map.get(service.meta, :account)
  end

  def put_service_account(name) do
    update_current(:service, &put_in(&1.meta[:account], name))
  end

  def unit_name(suffix \\ ".service") do
    prefixed(:unit, service_identity_name()) <> suffix
  end

  def service_identity_name do
    service = Process.get(@service_key) || raise "no HostKit service in scope"
    Map.get(service.meta, :identity_name, service_path_name())
  end

  def root_path(root, child \\ nil) do
    base =
      Path.join(Conventions.root!(project_conventions(), root), to_string(service_path_name()))

    case child do
      nil -> base
      value -> Path.join(base, to_string(value))
    end
  end

  def default_storage_path(:data), do: default_root_path(:data, "/var/lib")
  def default_storage_path(:state), do: default_root_path(:state, "/var/lib")
  def default_storage_path(:config), do: default_root_path(:config, "/etc")

  def default_storage_path(name),
    do:
      Path.join([
        default_root(:data, "/var/lib"),
        to_string(service_path_name()),
        to_string(name)
      ])

  def env_path(name, opts \\ []) do
    Keyword.get(opts, :path) ||
      Path.join([default_root(:config, "/etc"), to_string(service_path_name()), "#{name}.env"])
  end

  def put_env(name, path) do
    update_current(:service, fn service ->
      env_files = service.meta |> Map.get(:env_files, %{}) |> Map.put(name, path)
      %{service | meta: Map.put(service.meta, :env_files, env_files)}
    end)
  end

  def env_path!(name) do
    service = Process.get(@service_key) || raise "env/1 must be used inside service/2"
    service.meta |> Map.get(:env_files, %{}) |> Map.fetch!(name)
  end

  def prefixed(name, value), do: Conventions.prefixed(project_conventions(), name, value)

  def put_storage(name, opts) do
    volume = Storage.volume(name, storage_opts(name, opts))

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

  def put_endpoint(name, opts) do
    endpoint = HostKit.Endpoint.declaration(name, opts)

    update_current(:service, fn service ->
      endpoints = service.meta |> Map.get(:endpoints, %{}) |> Map.put(name, endpoint)
      %{service | meta: Map.put(service.meta, :endpoints, endpoints)}
    end)

    endpoint
  end

  def service_active?, do: Process.get(@service_key) != nil

  def listener(name) do
    service = Process.get(@service_key) || raise "no HostKit service in scope"
    service.meta |> Map.get(:listeners, %{}) |> Map.fetch!(name)
  end

  def listener_upstream(name), do: name |> listener() |> HostKit.Listener.upstream()

  defp update_proxy(fun) do
    proxy = Process.get(@proxy_key) || raise "proxy directive used outside proxy block"
    Process.put(@proxy_key, fun.(proxy))
    :ok
  end

  defp update_proxy_service(fun) do
    service =
      Process.get(@proxy_service_key) ||
        raise "proxy service directive used outside proxy service block"

    Process.put(@proxy_service_key, fun.(service))
    :ok
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
    case Process.get(@service_key) do
      nil -> update_project(&Project.add_resource(&1, resource))
      service -> Process.put(@service_key, Service.add_resource(service, resource))
    end

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

  defp service_path(name) do
    case Process.get(@workspace_key) do
      nil ->
        name

      workspace ->
        Path.join([to_string(workspace.owner), to_string(workspace.path_name), to_string(name)])
    end
  end

  defp service_identity(name) do
    case Process.get(@workspace_key) do
      nil ->
        name

      workspace ->
        Enum.join([workspace.owner, workspace.path_name, name], "-") |> String.replace("/", "-")
    end
  end

  defp maybe_put_workspace(meta) do
    case Process.get(@workspace_key) do
      nil -> meta
      workspace -> Map.put(meta, :workspace, Map.take(workspace, [:name, :owner]))
    end
  end

  defp storage_opts(opts) do
    opts = Keyword.put_new(opts, :owner, service_user())
    opts = Keyword.put_new(opts, :group, Keyword.fetch!(opts, :owner))

    case Keyword.pop(opts, :under) do
      {nil, opts} -> opts
      {root, opts} -> Keyword.put(opts, :path, root_path(root, Keyword.get(opts, :path)))
    end
  end

  defp storage_opts(name, opts) do
    opts =
      if Keyword.has_key?(opts, :under),
        do: opts,
        else: Keyword.put_new(opts, :path, default_storage_path(name))

    storage_opts(opts)
  end

  defp default_root_path(root, fallback) do
    Path.join(default_root(root, fallback), to_string(service_path_name()))
  end

  defp default_root(root, fallback) do
    Conventions.root(project_conventions(), root, fallback)
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
