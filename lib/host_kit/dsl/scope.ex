defmodule HostKit.DSL.Scope do
  @moduledoc false

  use HostKit.DSLCore

  alias HostKit.{
    Conventions,
    Host,
    Instance,
    Naming,
    Project,
    ProviderConfig,
    RPC,
    Service,
    Storage
  }

  @project_key {__MODULE__, :project}

  setting(:default_providers, default: [])

  options :proxy_opts do
    field(:provider, :atom, required: true)
    field(:path, :string, default: "/etc/gatehouse/config.exs")
    field(:meta, :map, default: %{})
  end

  options :firewall_opts do
    field(:path, :string, default: "/etc/nftables.d/hostkit.nft")
    field(:activate, :atom, default: :systemd, in: [:systemd, false])
    field(:unit, :any)
    field(:nft, :any)
    field(:description, :string)
    field(:after, :any)
    field(:before, :any)
    field(:wants, :any)
    field(:wanted_by, :any)
  end

  scope(:observability)

  scope :project, current: false, update: false do
    accepts(:host)
    accepts(:service)
    accepts(:resource)
  end

  scope(:host)

  scope :instance do
    accepts(:host)
    accepts(:service)
    accepts(:resource)
  end

  scope :service do
    accepts(:resource)
  end

  scope(:workspace)

  scope :proxy do
    accepts(:proxy_service, via: :add_service)
  end

  scope :proxy_service do
    requires(:proxy)
  end

  scope :backend_config do
    requires(:instance)
  end

  scope(:provider_config)
  scope(:mise)
  scope(:firewall)

  scope :ssh, value: true, start: false do
    requires(:host)
  end

  scope(:bootstrap, value: true)

  scope :inside, value: true do
    requires(:service)
  end

  scope :rpc, value: true do
    requires(:service)
  end

  def start_project(name, opts) do
    push_project(Project.new(name, project_opts(opts)))
  end

  defp project_opts(opts) do
    if Keyword.has_key?(opts, :providers) do
      opts
    else
      Keyword.put(opts, :providers, default_providers())
    end
  end

  def current_project do
    current_project!()
  end

  def finish_project do
    pop_project()
  end

  def start_observability do
    scope = if service_active?(), do: :service, else: :project
    push_observability(scope)
  end

  def finish_observability do
    pop_observability()
  end

  def put_observability(kind, value) do
    case current_observability() do
      :project -> update_project(&put_observability_value(&1, kind, value))
      :service -> update_current(:service, &put_observability_value(&1, kind, value))
      nil -> raise "no HostKit observability in scope"
    end
  end

  def start_firewall(opts \\ []) do
    scope = if host_active?(), do: :host, else: :project
    validated = validate_firewall_opts!(opts)

    activation_opts =
      opts
      |> Map.new()
      |> Map.take([:unit, :nft, :description, :after, :before, :wants, :wanted_by])

    firewall = %HostKit.Firewall{
      scope: scope,
      path: validated.path,
      activate: validated.activate,
      meta: activation_opts
    }

    push_firewall(firewall)
  end

  def finish_firewall do
    firewall = pop_firewall()

    case firewall.scope do
      :project -> update_project(&put_firewall_value(&1, firewall))
      :host -> update_current(:host, &put_firewall_value(&1, firewall))
    end
  end

  def add_firewall_rule(rule) do
    update_firewall(fn firewall ->
      %{firewall | rules: firewall.rules ++ [rule]}
    end)

    :ok
  end

  def put_providers(providers) do
    update_project(&Project.put_providers(&1, providers))
  end

  def start_provider_config(name, module) do
    push_provider_config(%ProviderConfig{
      name: name,
      module: module
    })
  end

  def start_mise(opts) do
    opts = Keyword.put_new(opts, :path, "/usr/local/bin/mise")
    opts = Keyword.put_new(opts, :system_data_dir, "/usr/local/share/mise")
    push_mise(HostKit.Resources.Mise.new(opts))
  end

  def add_tool(name, version, opts) do
    update_mise(&HostKit.Resources.Mise.add_tool(&1, name, version, opts))
    :ok
  end

  def finish_mise do
    mise = pop_mise()
    add_resource(mise)
  end

  def put_provider_config(key, value) do
    update_provider_config(fn config ->
      %{config | config: Map.put(config.config, key, value)}
    end)

    :ok
  end

  def finish_provider_config do
    config = pop_provider_config()
    update_project(&Project.put_provider_config(&1, config))
  end

  def put_tenant(name, opts) do
    update_project(&Project.add_tenant(&1, HostKit.Tenant.new(name, opts)))
  end

  def start_proxy(name, opts) do
    opts = validate_proxy_opts!(opts)

    push_proxy(%HostKit.Proxy{
      name: name,
      provider: opts.provider,
      path: opts.path,
      meta: opts.meta
    })
  end

  def finish_proxy do
    proxy = pop_proxy()
    update_project(&Project.add_proxy(&1, proxy))
  end

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
    push_proxy_service(HostKit.Proxy.service(name, opts))
  end

  def finish_proxy_service do
    service = pop_proxy_service()
    attach_proxy_service(service)
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
    host = %Host{
      name: name,
      hostname: Keyword.fetch!(opts, :at),
      user: nil,
      sudo: false,
      meta: Keyword.get(opts, :meta, %{})
    }

    push_host(host)
  end

  def start_ssh(opts \\ []) do
    push_ssh(true)
    put_ssh_opts(opts)
  end

  def put_ssh(key, value), do: put_ssh_opts([{key, value}])

  def put_ssh_opts(opts) do
    if host_active?() do
      update_current(:host, &put_host_ssh_opts(&1, opts))
    else
      raise "ssh directive used outside host block"
    end
  end

  def finish_host do
    host = pop_host()
    attach_host(host)
  end

  def start_instance(name, opts) do
    push_instance(Instance.new(name, opts))
  end

  def finish_instance do
    instance = pop_instance()
    update_project(&Project.add_instance(&1, instance))
  end

  def put_instance_backend(backend), do: update_instance(&Instance.put_backend(&1, backend))

  def put_instance_backend(backend, opts) do
    update_instance(fn instance ->
      instance
      |> Instance.put_backend(backend)
      |> Instance.put_backend_config(opts)
    end)
  end

  def start_backend_config(backend) do
    put_instance_backend(backend)
    push_backend_config(%{})
  end

  def finish_backend_config do
    config = pop_backend_config()
    update_instance(&Instance.put_backend_config(&1, config))
  end

  def put_backend_option(key, value) do
    update_backend_config(&Map.put(&1, key, value))
    :ok
  end

  def put_instance_image(image), do: update_instance(&Instance.put_image(&1, image))
  def put_instance_kind(kind), do: update_instance(&Instance.put_kind(&1, kind))

  def put_instance_lifecycle(lifecycle),
    do: update_instance(&Instance.put_lifecycle(&1, lifecycle))

  def put_instance_target_host(target_host),
    do: update_instance(&Instance.put_target_host(&1, target_host))

  def add_instance_port(name, opts), do: update_instance(&Instance.add_port(&1, name, opts))

  def start_service(name, opts) do
    base_name = Keyword.get(opts, :path, Keyword.get(opts, :as, name))

    service =
      name
      |> Service.new(opts)
      |> Map.put(:path, service_path(base_name))
      |> Map.put(:identity, service_identity(base_name))

    meta = service.meta |> maybe_put_workspace()

    push_service(%{service | meta: meta})
  end

  def finish_service do
    service = pop_service()
    attach_service(service)
  end

  def start_workspace(name, opts) do
    workspace = %{
      name: name,
      owner: Keyword.get(opts, :owner, name),
      path: Keyword.get(opts, :path, name),
      identity: Keyword.get(opts, :identity)
    }

    push_workspace(workspace)
  end

  def finish_workspace do
    pop_workspace()
    :ok
  end

  def add_inside_monitor(type, opts) do
    service_active?() || raise "inside monitors must be declared inside service/2"

    check = HostKit.Monitor.check(type, opts)

    update_current(:service, fn service ->
      monitors = service.meta |> Map.get(:inside_monitor, []) |> Kernel.++([check])
      %{service | meta: Map.put(service.meta, :inside_monitor, monitors)}
    end)

    :ok
  end

  def put_root(name, path), do: update_project(&Project.put_convention_root(&1, name, path))

  def put_prefix(name, prefix),
    do: update_project(&Project.put_convention_prefix(&1, name, prefix))

  def service_name do
    service = current_service!()
    service.name
  end

  def service_path do
    service = current_service!()
    service.path
  end

  def service_user do
    prefixed(:user, service_identity())
  end

  def service_account do
    service = current_service!()
    Map.get(service.meta, :account)
  end

  def put_service_account(name) do
    update_current(:service, &put_in(&1.meta[:account], name))
  end

  def unit_name(suffix \\ ".service") do
    :unit
    |> prefixed(service_identity())
    |> Naming.systemd_unit(suffix)
  end

  def service_identity do
    service = current_service!()
    service.identity
  end

  def path(root, child \\ nil) do
    base = Conventions.root!(project_conventions(), root)

    base =
      if service_scoped_path?(root) do
        Path.join(base, service_path())
      else
        base
      end

    case child do
      nil -> base
      value -> Path.join(base, to_string(value))
    end
  end

  defp service_scoped_path?(root) when root in [:source, :data, :state, :cache, :config, :run],
    do: service_active?()

  defp service_scoped_path?(_root), do: false

  def default_storage_path(:data), do: default_path(:data, "/var/lib")
  def default_storage_path(:state), do: default_path(:state, "/var/lib")
  def default_storage_path(:config), do: default_path(:config, "/etc")

  def default_storage_path(name),
    do:
      Path.join([
        default_root(:data, "/var/lib"),
        service_path(),
        to_string(name)
      ])

  def env_path(name, opts \\ []) do
    Keyword.get(opts, :path) ||
      Path.join([default_root(:config, "/etc"), service_path(), "#{name}.env"])
  end

  def put_env(name, path) do
    update_current(:service, fn service ->
      env_files = service.meta |> Map.get(:env_files, %{}) |> Map.put(name, path)
      %{service | meta: Map.put(service.meta, :env_files, env_files)}
    end)
  end

  def env_path!(name) do
    service_active?() || raise "env/1 must be used inside service/2"
    service = current_service!()
    service.meta |> Map.get(:env_files, %{}) |> Map.fetch!(name)
  end

  def prefixed(name, value), do: Conventions.prefixed(project_conventions(), name, value)

  def put_release(name, opts) do
    release_name = to_string(name)
    version = Keyword.fetch!(opts, :version)
    release_owner = Keyword.get(opts, :owner, "root")
    release_group = Keyword.get(opts, :group, release_owner)
    release_mode = Keyword.get(opts, :mode, 0o755)
    current_owner = Keyword.get(opts, :current_owner)
    current_group = Keyword.get(opts, :current_group)

    releases_dir =
      Keyword.get(opts, :releases_dir) || path(:opt, Path.join("releases", release_name))

    current_path =
      Keyword.get(opts, :current_path) || path(:opt, Path.join("current", release_name))

    release_path =
      Keyword.get(opts, :release_path) || Path.join(releases_dir, to_string(version))

    add_resource(
      HostKit.Resources.Directory.new(releases_dir,
        owner: release_owner,
        group: release_group,
        mode: release_mode
      )
    )

    maybe_add_release_current_dir(current_path, opts)

    add_resource(
      HostKit.Resources.Symlink.new(current_path,
        to: release_path,
        owner: current_owner,
        group: current_group
      )
    )

    metadata = %{
      name: release_name,
      kind: :release,
      version: to_string(version),
      releases_dir: releases_dir,
      release_path: release_path,
      current_path: current_path,
      keep: Keyword.get(opts, :keep)
    }

    put_release_metadata(release_name, metadata)

    %{
      name: release_name,
      version: to_string(version),
      releases_dir: releases_dir,
      release_path: release_path,
      current_path: current_path
    }
  end

  def put_release_metadata(name, metadata) do
    if service_active?() do
      update_current(:service, fn service ->
        releases = service.meta |> Map.get(:releases, %{}) |> Map.put(name, metadata)
        %{service | meta: Map.put(service.meta, :releases, releases)}
      end)
    else
      :ok
    end
  end

  defp maybe_add_release_current_dir(current_path, opts) do
    case Keyword.get(opts, :current_dir) do
      current_dir_opts when is_list(current_dir_opts) ->
        path = Keyword.get(current_dir_opts, :path, Path.dirname(current_path))

        add_resource(
          HostKit.Resources.Directory.new(path,
            owner: Keyword.get(current_dir_opts, :owner, "root"),
            group: Keyword.get(current_dir_opts, :group, "root"),
            mode: Keyword.get(current_dir_opts, :mode, 0o755)
          )
        )

      _other ->
        :ok
    end
  end

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
    service = current_service!()
    service.meta |> Map.get(:storage, %{}) |> Map.fetch!(name)
  end

  def storage_path(name), do: storage_volume(name).path

  def writable_storage_paths do
    service = current_service!()
    service.meta |> Map.get(:storage, %{}) |> Map.values() |> Storage.read_write_paths()
  end

  def backup_storage do
    service = current_service!()

    service.meta
    |> Map.get(:storage, %{})
    |> Enum.filter(fn {_name, volume} -> Storage.backup?(volume) end)
    |> Enum.map(fn {_name, volume} -> volume end)
  end

  def put_listener(name, opts) do
    listener = HostKit.Listener.new(name, default_listener_opts(name, opts))

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

  def listener(name) do
    service = current_service!()
    service.meta |> Map.get(:listeners, %{}) |> Map.fetch!(name)
  end

  def listener_upstream(name), do: name |> listener() |> HostKit.Listener.upstream()

  def put_rpc_exposure(name, opts \\ []) do
    exposure = HostKit.RPC.Exposure.new(name, opts)

    update_current(:service, fn service ->
      rpc = service.meta |> Map.get(:rpc, RPC.new()) |> RPC.add_exposure(exposure)
      %{service | meta: Map.put(service.meta, :rpc, rpc)}
    end)

    exposure
  end

  def put_rpc_binding(service_name, opts \\ []) do
    binding = HostKit.RPC.Binding.new(service_name, opts)

    update_current(:service, fn service ->
      rpc = service.meta |> Map.get(:rpc, RPC.new()) |> RPC.add_binding(binding)
      %{service | meta: Map.put(service.meta, :rpc, rpc)}
    end)

    binding
  end

  defp default_listener_opts(_name, opts) do
    opts = default_rpc_socket(opts)

    if Keyword.get(opts, :protocol) == :rpc do
      Keyword.update(
        opts,
        :meta,
        default_rpc_socket_meta(),
        &Map.merge(default_rpc_socket_meta(), &1)
      )
    else
      opts
    end
  end

  defp default_rpc_socket(opts) do
    if Keyword.get(opts, :protocol) == :rpc and is_nil(Keyword.get(opts, :port)) and
         is_nil(Keyword.get(opts, :socket)) do
      Keyword.put(
        opts,
        :socket,
        path(:run, "rpc.sock")
      )
    else
      opts
    end
  end

  defp default_rpc_socket_meta do
    %{
      socket_owner: service_user(),
      socket_group: service_user(),
      socket_mode: 0o660
    }
  end

  defp put_host_ssh_opts(host, opts) do
    host
    |> maybe_put_host_user(Keyword.get(opts, :user))
    |> maybe_put_host_sudo(opts)
    |> update_in([Access.key(:meta), :ssh], &Keyword.merge(&1 || [], opts))
  end

  defp maybe_put_host_user(host, nil), do: host
  defp maybe_put_host_user(host, user), do: %{host | user: user}

  defp maybe_put_host_sudo(host, opts) do
    if Keyword.has_key?(opts, :sudo), do: %{host | sudo: Keyword.fetch!(opts, :sudo)}, else: host
  end

  def update_current(:host, fun) do
    update_host(fun)
    :ok
  end

  def update_current(:service, fun) do
    update_service(fun)
    :ok
  end

  def add_resource(resource) do
    attach(:resource, resource)
  end

  def update_last_resource(fun) do
    service_active?() || raise "resources must be declared inside service/2"
    service = current_service!()

    case service.resources do
      [] ->
        raise "no HostKit resource in scope"

      resources ->
        {last, rest_reversed} = resources |> Enum.reverse() |> List.pop_at(0)

        update_service(fn service ->
          %{service | resources: Enum.reverse(rest_reversed, [fun.(last)])}
        end)

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
    case current_workspace() do
      nil ->
        Naming.path_segment(name)

      workspace ->
        Naming.workspace_path(workspace.owner, workspace.path, name)
    end
  end

  defp service_identity(name) do
    case current_workspace() do
      nil ->
        Naming.identity_segment(name)

      workspace ->
        Naming.workspace_identity(workspace.owner, workspace.path, name)
    end
  end

  defp maybe_put_workspace(meta) do
    case current_workspace() do
      nil -> meta
      workspace -> Map.put(meta, :workspace, Map.take(workspace, [:name, :owner]))
    end
  end

  defp storage_opts(opts) do
    opts = Keyword.put_new(opts, :owner, service_user())
    opts = Keyword.put_new(opts, :group, Keyword.fetch!(opts, :owner))

    case Keyword.pop(opts, :under) do
      {nil, opts} -> opts
      {root, opts} -> Keyword.put(opts, :path, path(root, Keyword.get(opts, :path)))
    end
  end

  defp storage_opts(name, opts) do
    opts =
      if Keyword.has_key?(opts, :under),
        do: opts,
        else: Keyword.put_new(opts, :path, default_storage_path(name))

    storage_opts(opts)
  end

  defp default_path(root, fallback) do
    Path.join(default_root(root, fallback), service_path())
  end

  defp default_root(root, fallback) do
    Conventions.root(project_conventions(), root, fallback)
  end

  defp project_conventions do
    current_project().conventions
  end

  defp update_project(fun) do
    DSLCore.update(@project_key, fun)
    :ok
  end
end
