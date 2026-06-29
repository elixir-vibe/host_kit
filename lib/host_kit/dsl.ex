defmodule HostKit.DSL do
  @moduledoc """
  Core HostKit DSL.

  The DSL is only a builder: it evaluates `.exs` declarations into plain HostKit
  structs and does not apply changes to the host.
  """

  use DSL.Macros

  alias HostKit.DSL.{ConfigFile, EnvFile, Ingress, Lifecycle, Readiness, Scope}
  alias HostKit.DSL.Systemd.Scope, as: SystemdScope
  alias HostKit.Providers.Caddy.Scope, as: CaddyScope
  alias HostKit.Resources

  defmacro __using__(opts) do
    providers =
      opts
      |> Keyword.get(:providers, [])
      |> Enum.map(&Macro.expand(&1, __CALLER__))
      |> HostKit.Provider.resolve()

    recipes =
      opts
      |> Keyword.get(:recipes, [])
      |> Enum.map(&Macro.expand(&1, __CALLER__))

    import_sigils? = Keyword.get(opts, :sigils, true)

    provider_imports =
      providers
      |> HostKit.Provider.dsl_modules()
      |> Enum.map(fn dsl ->
        quote do
          import unquote(dsl)
        end
      end)

    recipe_imports =
      Enum.map(recipes, fn recipe ->
        quote do
          import unquote(recipe)
        end
      end)

    sigil_import =
      if import_sigils? do
        quote do
          import HostKit.Sigils
        end
      end

    quote do
      Scope.put_default_providers(unquote(providers))
      import HostKit.DSL
      import HostKit.DSL.Systemd
      unquote(sigil_import)
      unquote_splicing(provider_imports)
      unquote_splicing(recipe_imports)
    end
  end

  defblock project(name, opts \\ []) do
    start(Scope.start_project(name, opts))
    finish(Scope.finish_project())
  end

  defdirective providers(providers) do
    Scope.put_providers(providers)
  end

  defmacro roots(values) do
    quote do
      Enum.each(unquote(values), fn {name, path} -> Scope.put_root(name, path) end)
    end
  end

  defmacro prefixes(values) do
    quote do
      Enum.each(unquote(values), fn {name, prefix} ->
        Scope.put_prefix(name, prefix)
      end)
    end
  end

  defblock provider(name, module) do
    start(Scope.start_provider_config(name, module))
    finish(Scope.finish_provider_config())
  end

  defmacro set(key, value) do
    quote do
      cond do
        EnvFile.Scope.active?() ->
          EnvFile.Scope.put_set(unquote(key), unquote(value))

        ConfigFile.Scope.active?() ->
          ConfigFile.Scope.put_set(unquote(key), unquote(value))

        true ->
          Scope.put_provider_config(unquote(key), unquote(value))
      end
    end
  end

  defblock dotenv(path, opts \\ []) do
    start(EnvFile.Scope.start(path, opts))
    finish(Scope.add_resource(EnvFile.Scope.finish()))
  end

  defmacro env_file(path, opts \\ [], do: block) do
    quote do
      dotenv unquote(path), unquote(opts) do
        unquote(block)
      end
    end
  end

  defmacro env(name, opts \\ [], do: block) do
    quote do
      path = Scope.env_path(unquote(name), unquote(opts))

      opts =
        unquote(opts)
        |> Keyword.put_new(:owner, "root")
        |> Keyword.put_new(:group, service_user())

      EnvFile.Scope.start(path, opts)
      unquote(block)
      Scope.put_env(unquote(name), path)
      Scope.add_resource(EnvFile.Scope.finish())
    end
  end

  defmacro env(name) do
    quote do
      path = Scope.env_path!(unquote(name))
      SystemdScope.put_service(:environment_file, path)
      path
    end
  end

  defblock ready(name, opts \\ []), source: true do
    start(Readiness.Scope.start(name, opts, source))
    finish(Scope.add_resource(Readiness.Scope.finish()))
  end

  defblock ingress(name, opts \\ []), source: true do
    start(Ingress.Scope.start_ingress(name, opts, source))
    finish(Scope.add_resource(Ingress.Scope.finish_ingress()))
  end

  defblock server(listen \\ ":443", opts \\ []), source: true do
    start(Ingress.Scope.start_server(listen, opts, source))
    finish(Ingress.Scope.finish_server())
  end

  defmacro tls(mode, opts \\ []) do
    source = DSL.Source.escape_caller(__CALLER__)

    quote do
      if Scope.proxy_service_active?() do
        Scope.put_proxy_tls(unquote(mode))
      else
        Ingress.Scope.put_tls(unquote(mode), unquote(opts), unquote(source))
      end
    end
  end

  defblock route(opts), source: true do
    start(Ingress.Scope.start_route(opts, source))
    finish(Ingress.Scope.finish_route())
  end

  defmacro proxy(opts) do
    source = DSL.Source.escape_caller(__CALLER__)

    quote do
      Ingress.Scope.put_proxy(unquote(opts), unquote(source))
    end
  end

  defmacro systemd(unit, opts \\ []) do
    source = DSL.Source.escape_caller(__CALLER__)

    quote do
      Readiness.Scope.add_check(
        Readiness.Scope.systemd_check(unquote(unit), unquote(opts), unquote(source))
      )
    end
  end

  defmacro http(url_or_opts \\ []) do
    source = DSL.Source.escape_caller(__CALLER__)

    quote do
      cond do
        Readiness.Scope.active?() ->
          Readiness.Scope.add_check(
            Readiness.Scope.http_check(unquote(url_or_opts), [], unquote(source))
          )

        Scope.proxy_active?() ->
          Scope.put_proxy_listener(:http, unquote(url_or_opts))

        true ->
          raise ArgumentError, "http/1 is only supported inside ready/2 or proxy/3"
      end
    end
  end

  defmacro http(url, opts) do
    source = DSL.Source.escape_caller(__CALLER__)

    quote do
      cond do
        Readiness.Scope.active?() ->
          Readiness.Scope.add_check(
            Readiness.Scope.http_check(unquote(url), unquote(opts), unquote(source))
          )

        Scope.proxy_active?() ->
          raise ArgumentError, "proxy http listener expects keyword options, got two arguments"

        true ->
          raise ArgumentError, "http/2 is only supported inside ready/2"
      end
    end
  end

  defmacro https(opts \\ []) do
    quote do
      Scope.put_proxy_listener(:https, unquote(opts))
    end
  end

  defdirective(state(path)) do
    Scope.put_proxy_state(path)
  end

  defdirective(acme(opts)) do
    Scope.put_proxy_acme(opts)
  end

  defdirective(balance(policy, opts \\ [])) do
    Scope.put_proxy_balance(policy, opts)
  end

  defdirective(health(path, opts \\ [])) do
    Scope.put_proxy_health(path, opts)
  end

  defdirective(drain(timeout)) do
    Scope.put_proxy_drain(timeout)
  end

  defmacro secret(key, opts) do
    quote do
      if ConfigFile.Scope.active?() do
        ConfigFile.Scope.put_secret(unquote(key), unquote(opts))
      else
        EnvFile.Scope.put_secret(unquote(key), unquote(opts))
      end
    end
  end

  defmacro tenant(name, opts \\ [], do: block) do
    quote do
      Scope.put_tenant(unquote(name), unquote(opts))

      workspace unquote(name), Keyword.put_new(unquote(opts), :owner, unquote(name)) do
        unquote(block)
      end
    end
  end

  defmacro host(name, opts \\ []) do
    case Keyword.pop(opts, :do) do
      {nil, _opts} ->
        quote do
          if Scope.proxy_active?() do
            Scope.add_proxy_host(unquote(name))
          else
            raise ArgumentError, "host/2 without a block is only supported inside proxy/3"
          end
        end

      {block, opts} ->
        quote do
          Scope.start_host(unquote(name), unquote(opts))
          unquote(block)
          Scope.finish_host()
        end
    end
  end

  defmacro host(name, opts, do: block) do
    quote do
      Scope.start_host(unquote(name), unquote(opts))
      unquote(block)
      Scope.finish_host()
    end
  end

  defblock(instance(name, opts \\ [])) do
    start(Scope.start_instance(name, opts))
    finish(Scope.finish_instance())
  end

  defmacro backend(name) do
    quote do
      Scope.put_instance_backend(unquote(name))
    end
  end

  defmacro backend(name, [{:do, block}]) do
    quote do
      Scope.start_backend_config(unquote(name))
      unquote(block)
      Scope.finish_backend_config()
    end
  end

  defmacro backend(name, opts) when is_list(opts) do
    quote do
      Scope.put_instance_backend(unquote(name), unquote(opts))
    end
  end

  defdirective(option(key, value)) do
    Scope.put_backend_option(key, value)
  end

  defdirective(image(value)) do
    Scope.put_instance_image(value)
  end

  defdirective(kind(value)) do
    Scope.put_instance_kind(value)
  end

  defdirective(lifecycle(value)) do
    Scope.put_instance_lifecycle(value)
  end

  defdirective(target_host(name)) do
    Scope.put_instance_target_host(name)
  end

  defmacro expose(name, opts \\ []) do
    quote do
      if Scope.rpc_active?() do
        Scope.put_rpc_exposure(unquote(name), unquote(opts))
      else
        Scope.add_instance_port(unquote(name), unquote(opts))
      end
    end
  end

  defblock proxy(name, opts), source: true do
    start(Scope.start_proxy(name, opts, source))
    finish(Scope.finish_proxy())
  end

  defmacro service(name, opts \\ [], do: block) do
    quote do
      if Scope.proxy_active?() do
        Scope.start_proxy_service(unquote(name), unquote(opts))
        unquote(block)
        Scope.finish_proxy_service()
      else
        Scope.start_service(unquote(name), unquote(opts))
        unquote(block)
        Scope.finish_service()
      end
    end
  end

  defblock(workspace(name, opts)) do
    start(Scope.start_workspace(name, opts))
    finish(Scope.finish_workspace())
  end

  defmacro put_in_meta(key, value) do
    quote do
      Scope.update_current(:service, &put_in(&1.meta[unquote(key)], unquote(value)))
    end
  end

  defdirective(service_name()) do
    Scope.service_name()
  end

  defdirective(service_path()) do
    Scope.service_path()
  end

  defdirective(service_user()) do
    Scope.service_user()
  end

  defdirective(unit_name(suffix \\ ".service")) do
    Scope.unit_name(suffix)
  end

  defdirective(path(root, child \\ nil)) do
    Scope.path(root, child)
  end

  defdirective(release(name, opts)) do
    Scope.put_release(name, opts)
  end

  defdirective(storage(name, opts)) do
    Scope.put_storage(name, opts)
  end

  defdirective(storage_volume(name)) do
    Scope.storage_volume(name)
  end

  defdirective(storage_path(name)) do
    Scope.storage_path(name)
  end

  defdirective(writable_storage_paths()) do
    Scope.writable_storage_paths()
  end

  defdirective(backup_storage()) do
    Scope.backup_storage()
  end

  defdirective(target(name, opts)) do
    Scope.add_proxy_target(name, opts)
  end

  defdirective(user(value)) do
    Scope.put_ssh(:user, value)
  end

  defdirective(sudo(value)) do
    Scope.put_ssh(:sudo, value)
  end

  defmacro ssh(do: block) do
    quote do
      Scope.start_ssh([])
      unquote(block)
      Scope.finish_ssh()
    end
  end

  defmacro ssh(opts) do
    quote do
      Scope.start_ssh(unquote(opts))
      Scope.finish_ssh()
    end
  end

  defmacro ssh(opts, do: block) do
    quote do
      Scope.start_ssh(unquote(opts))
      unquote(block)
      Scope.finish_ssh()
    end
  end

  defdirective(identity_file(path)) do
    Scope.put_ssh(:identity_file, path)
  end

  defdirective(password(value)) do
    Scope.put_ssh(:password, value)
  end

  defdirective(port(value)) do
    Scope.put_ssh(:port, value)
  end

  defdirective(accept_hosts(value)) do
    Scope.put_ssh(:silently_accept_hosts, value)
  end

  defdirective(retry(opts)) do
    Scope.put_ssh(:retry, opts)
  end

  defblock(bootstrap()) do
    start(Scope.start_bootstrap())
    finish(Scope.finish_bootstrap())
  end

  defmacro secret_env(name) do
    quote do
      HostKit.Secret.env(unquote(name))
    end
  end

  defblock(observability()) do
    start(Scope.start_observability())
    finish(Scope.finish_observability())
  end

  defblock firewall(opts \\ []), source: true do
    start(Scope.start_firewall(opts, source))
    finish(Scope.finish_firewall())
  end

  defmacro allow(opts) do
    quote do
      Scope.add_firewall_rule(HostKit.Firewall.allow(unquote(opts)))
    end
  end

  defmacro deny(target, opts \\ []) do
    quote do
      Scope.add_firewall_rule(HostKit.Firewall.deny(unquote(target), unquote(opts)))
    end
  end

  defmacro egress(opts) do
    quote do
      user = service_user()
      policy = HostKit.Workspace.Egress.new(Keyword.put_new(unquote(opts), :user, user))
      Scope.update_current(:service, &put_in(&1.meta[:egress], policy))
    end
  end

  defmacro rpc(do: block) do
    quote do
      Scope.start_rpc()
      unquote(block)
      Scope.finish_rpc()
    end
  end

  defdirective(bind(service, opts \\ [])) do
    Scope.put_rpc_binding(service, opts)
  end

  defblock(inside()) do
    start(Scope.start_inside())
    finish(Scope.finish_inside())
  end

  defdirective(inside_monitor(type, opts \\ [])) do
    Scope.add_inside_monitor(type, opts)
  end

  defmacro agent(opts \\ []) do
    quote do
      service Keyword.get(unquote(opts), :service, :agent) do
        account(service_user(), system: true)

        directory(path(:data),
          owner: service_user(),
          group: service_user(),
          mode: :private_dir
        )

        daemon unit_name() do
          service_user(service_user())
          service_group(service_user())
          working_directory(path(:data))

          run(
            exec_start:
              Keyword.get(unquote(opts), :exec_start, ["/usr/local/bin/hostkit-workspace-agent"])
          )

          restart(:on_failure)
          wanted_by(:multi_user)
          listen(:agent, port: Keyword.get(unquote(opts), :port, 4173), on: :loopback)

          put_in_meta(
            :agent_socket,
            Keyword.get(unquote(opts), :socket, "/run/hostkit/workspaces/#{service_user()}.sock")
          )

          logs(identifier: service_user(), stdout: :journal, stderr: :journal)
          telemetry(logs: true, metrics: true, service_name: service_user())
          monitor(:systemd, expect: [state: :active], severity: :critical)
          network_policy(deny: :all, allow: [:loopback])
        end
      end
    end
  end

  defmacro workspace_agent(opts \\ []) do
    quote do
      agent(unquote(opts))
    end
  end

  defmacro telemetry(opts) do
    quote do
      if Scope.observability_active?() do
        Scope.put_observability(:telemetry, HostKit.Telemetry.config(unquote(opts)))
      else
        HostKit.DSL.attach_telemetry(unquote(opts))
      end
    end
  end

  defmacro logs(opts) do
    quote do
      if Scope.observability_active?() do
        Scope.put_observability(:logs, HostKit.Logs.config(unquote(opts)))
      else
        HostKit.DSL.attach_logs(unquote(opts))
      end
    end
  end

  def attach_telemetry(opts) do
    config = HostKit.Telemetry.config(opts)

    cond do
      SystemdScope.active?() ->
        SystemdScope.put_telemetry(config)

      Code.ensure_loaded?(CaddyScope) and
          CaddyScope.active?() ->
        CaddyScope.put_telemetry(config)

      true ->
        Scope.update_last_resource(&put_in(&1.meta[:telemetry], config))
    end
  end

  def attach_logs(opts) do
    config = HostKit.Logs.config(opts)

    cond do
      SystemdScope.active?() ->
        SystemdScope.put_logs(config)

      Code.ensure_loaded?(CaddyScope) and
          CaddyScope.active?() ->
        CaddyScope.put_logs(config)

      true ->
        Scope.update_last_resource(&put_in(&1.meta[:logs], config))
    end
  end

  defblock(isolate()) do
    start(SystemdScope.start_isolation(:strict_app, []))
    finish(SystemdScope.finish_isolation())
  end

  defblock(isolate(profile, opts \\ [])) do
    start(SystemdScope.start_isolation(profile, opts))
    finish(SystemdScope.finish_isolation())
  end

  defdirective(memory_max(value)) do
    SystemdScope.put_isolation_resource(:memory_max, value)
  end

  defmacro writable(name) when is_atom(name) do
    quote do
      SystemdScope.put_isolation_sandbox(
        :read_write_paths,
        Scope.storage_path(unquote(name))
      )
    end
  end

  defmacro writable(path) do
    quote do
      SystemdScope.put_isolation_sandbox(:read_write_paths, unquote(path))
    end
  end

  defdirective(private_network(value)) do
    SystemdScope.put_isolation_sandbox(:private_network, value)
  end

  defmacro network(:loopback) do
    quote do
      SystemdScope.put_isolation_network(:loopback)
    end
  end

  defdirective(network_policy(opts)) do
    SystemdScope.put_network_policy(opts)
  end

  defdirective(listen(name_or_port, opts \\ [])) do
    HostKit.DSL.attach_listener(name_or_port, opts)
  end

  defdirective(listener(name)) do
    Scope.listener_upstream(name)
  end

  defmacro preview(name, opts) do
    quote do
      listen(unquote(name),
        port: Keyword.fetch!(unquote(opts), :port),
        on: Keyword.get(unquote(opts), :on, :loopback)
      )

      caddy_site unquote(name), Keyword.fetch!(unquote(opts), :domain) do
        reverse_proxy(listener(unquote(name)))

        monitor(:http,
          url: "https://#{Keyword.fetch!(unquote(opts), :domain)}",
          expect: [status: Keyword.get(unquote(opts), :status, 200)]
        )

        telemetry(logs: true, metrics: :http, service_name: to_string(unquote(name)))
        logs(driver: :caddy_access, format: :json, ship: true)
      end
    end
  end

  def attach_listener(name, opts) when is_atom(name) do
    listener = Scope.put_listener(name, opts)

    if SystemdScope.active?() and is_integer(listener.port) do
      SystemdScope.put_listen(listener.port, on: listener.on)
    end

    listener
  end

  def attach_listener(port, opts) when is_integer(port) do
    SystemdScope.put_listen(port, opts)
  end

  defmacro monitor(type, opts \\ []) do
    quote do
      cond do
        Scope.inside_active?() ->
          Scope.add_inside_monitor(unquote(type), unquote(opts))

        SystemdScope.active?() ->
          SystemdScope.put_monitor(unquote(type), unquote(opts))

        Code.ensure_loaded?(CaddyScope) and
            CaddyScope.active?() ->
          CaddyScope.put_monitor(unquote(type), unquote(opts))

        true ->
          Scope.update_last_resource(fn resource ->
            resource_id = HostKit.Resource.id(resource)

            check =
              HostKit.Monitor.check(
                unquote(type),
                Keyword.put(unquote(opts), :resource_id, resource_id)
              )

            update_in(resource.meta[:monitor], &(List.wrap(&1) ++ [check]))
          end)
      end
    end
  end

  defmacro account(opts) when is_list(opts) do
    quote do
      account(service_user(), unquote(opts))
    end
  end

  defmacro account(name) do
    quote do
      HostKit.Account.ref(unquote(name))
    end
  end

  defmacro account(name, opts) do
    quote do
      account_name = HostKit.Account.name!(unquote(name))

      Scope.add_resource(%Resources.Account{
        name: account_name,
        system: Keyword.get(unquote(opts), :system, false),
        home: Keyword.get(unquote(opts), :home),
        shell: Keyword.get(unquote(opts), :shell, "/usr/sbin/nologin"),
        groups: Keyword.get(unquote(opts), :groups, []),
        rollback: Keyword.get(unquote(opts), :rollback, :keep),
        meta: Keyword.get(unquote(opts), :meta, %{})
      })

      if Scope.service_active?() do
        Scope.put_service_account(account_name)
      end
    end
  end

  defdirective(directory(path, opts \\ [])) do
    Scope.add_resource(Resources.Directory.new(path, opts))
  end

  defmacro endpoint(name_or_service, name_or_opts \\ :default, opts \\ []) do
    source = HostKit.SourceLocation.from_caller(__CALLER__)

    quote do
      if Scope.service_active?() and is_list(unquote(name_or_opts)) and
           unquote(opts) == [] do
        declaration_opts =
          HostKit.DSL.put_source_meta(unquote(name_or_opts), unquote(Macro.escape(source)))

        Scope.put_endpoint(unquote(name_or_service), declaration_opts)
      else
        ref_opts = HostKit.DSL.put_source_meta(unquote(opts), unquote(Macro.escape(source)))
        HostKit.Endpoint.new(unquote(name_or_service), unquote(name_or_opts), ref_opts)
      end
    end
  end

  defmacro source(name, opts) do
    source = HostKit.SourceLocation.from_caller(__CALLER__)

    quote do
      opts =
        Keyword.update(
          unquote(opts),
          :meta,
          %{source: unquote(Macro.escape(source))},
          &Map.put(&1, :source, unquote(Macro.escape(source)))
        )

      Scope.add_resource(Resources.Source.new(unquote(name), opts))
    end
  end

  def put_source_meta(opts, source) do
    Keyword.update(opts, :meta, %{source: source}, &Map.put(&1, :source, source))
  end

  defmacro package(name, opts \\ []) do
    source = HostKit.SourceLocation.from_caller(__CALLER__)

    quote do
      opts =
        Keyword.update(
          unquote(opts),
          :meta,
          %{source: unquote(Macro.escape(source))},
          &Map.put(&1, :source, unquote(Macro.escape(source)))
        )

      Scope.add_resource(Resources.Package.new(unquote(name), opts))
    end
  end

  defdirective(packages(names, opts \\ [])) do
    Enum.each(names, &package(&1, opts))
  end

  defdirective(file(path, opts \\ [])) do
    Scope.add_resource(Resources.File.new(path, opts))
  end

  defmacro template(path, opts) do
    base_dir = __CALLER__.file |> Path.dirname() |> Path.expand()

    quote do
      opts = Keyword.put_new(unquote(opts), :base_dir, unquote(base_dir))
      Scope.add_resource(Resources.Template.new(unquote(path), opts))
    end
  end

  defdirective(ini(path, opts \\ [])) do
    Scope.add_resource(Resources.ConfigFile.new(path, :ini, opts))
  end

  defblock(ini(path, opts)) do
    start(ConfigFile.Scope.start(path, :ini, opts))
    finish(Scope.add_resource(ConfigFile.Scope.finish()))
  end

  defdirective(yaml(path, opts)) do
    Scope.add_resource(Resources.ConfigFile.new(path, :yaml, opts))
  end

  defdirective(toml(path, opts)) do
    Scope.add_resource(Resources.ConfigFile.new(path, :toml, opts))
  end

  defmacro exs(path, opts \\ [], do: block) do
    ast = Macro.escape(block)

    quote do
      Scope.add_resource(Resources.Exs.new(unquote(path), unquote(ast), unquote(opts)))
    end
  end

  defblock(section(name)) do
    start(ConfigFile.Scope.start_section(name))
    finish(ConfigFile.Scope.finish_section())
  end

  defdirective(symlink(path, opts)) do
    Scope.add_resource(Resources.Symlink.new(path, opts))
  end

  defblock(before_start(name, opts \\ [])) do
    start(Lifecycle.Scope.start(name, :before_start, opts))
    finish(Lifecycle.Scope.finish())
  end

  defblock(after_start(name, opts \\ [])) do
    start(Lifecycle.Scope.start(name, :after_start, opts))
    finish(Lifecycle.Scope.finish())
  end

  defblock(before_stop(name, opts \\ [])) do
    start(Lifecycle.Scope.start(name, :before_stop, opts))
    finish(Lifecycle.Scope.finish())
  end

  defblock(after_stop(name, opts \\ [])) do
    start(Lifecycle.Scope.start(name, :after_stop, opts))
    finish(Lifecycle.Scope.finish())
  end

  defmacro command(name, opts) do
    source = HostKit.SourceLocation.from_caller(__CALLER__)

    quote do
      opts =
        Keyword.update(
          unquote(opts),
          :meta,
          %{source: unquote(Macro.escape(source))},
          &Map.put(&1, :source, unquote(Macro.escape(source)))
        )

      Scope.add_resource(Resources.Command.new(unquote(name), opts))
    end
  end

  defmacro run(name, command, opts \\ []) do
    quote do
      command(unquote(name), Keyword.put(unquote(opts), :exec, unquote(command)))
    end
  end

  defmacro git(name, command, opts \\ []) do
    quote do
      command(
        unquote(name),
        Keyword.put(unquote(opts), :exec, HostKit.DSL.git_exec(unquote(command)))
      )
    end
  end

  defmacro bash(name, script, opts \\ []) do
    source = HostKit.SourceLocation.from_caller(__CALLER__)

    quote do
      opts =
        Keyword.update(
          unquote(opts),
          :meta,
          %{source: unquote(Macro.escape(source))},
          &Map.put(&1, :source, unquote(Macro.escape(source)))
        )

      Scope.add_resource(Resources.Shell.new(unquote(name), unquote(script), opts))
    end
  end

  defdirective(argv(command, opts \\ [])) do
    HostKit.CommandLine.argv(command, opts)
  end

  defmacro mix(task, opts \\ []) do
    quote do
      opts = Keyword.put_new(unquote(opts), :command, path(:bin, "mix"))
      HostKit.CommandLine.mix(unquote(task), opts)
    end
  end

  defmacro elixir(opts \\ []) do
    quote do
      opts = Keyword.put_new(unquote(opts), :command, path(:bin, "elixir"))
      HostKit.CommandLine.elixir(opts)
    end
  end

  defmacro elixir(script_or_args, opts) do
    quote do
      opts = Keyword.put_new(unquote(opts), :command, path(:bin, "elixir"))
      HostKit.CommandLine.elixir(unquote(script_or_args), opts)
    end
  end

  defmacro eval(expression, opts \\ []) do
    expression =
      case expression do
        expression when is_binary(expression) -> expression
        expression -> Macro.to_string(expression)
      end

    quote do
      opts = Keyword.put_new(unquote(opts), :command, path(:bin, "elixir"))

      if Lifecycle.Scope.active?() do
        Lifecycle.Scope.put_exec(Lifecycle.Scope.eval_exec(unquote(expression), opts))
      else
        HostKit.CommandLine.eval(unquote(expression), opts)
      end
    end
  end

  def git_exec(%HostKit.CommandLine{} = command), do: {"git", [command.command | command.args]}

  def git_exec(command) when is_binary(command),
    do: command |> HostKit.CommandLine.parse!() |> git_exec()

  def git_exec(args) when is_list(args), do: ["git" | args]

  defblock(mise(opts \\ [])) do
    start(Scope.start_mise(opts))
    finish(Scope.finish_mise())
  end

  defdirective(tool(name, version, opts \\ [])) do
    Scope.add_tool(name, version, opts)
  end
end
