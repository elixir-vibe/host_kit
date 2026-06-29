defmodule HostKit.DSL do
  @moduledoc """
  Core HostKit DSL.

  The DSL is only a builder: it evaluates `.exs` declarations into plain HostKit
  structs and does not apply changes to the host.
  """

  use DSL.Macros

  alias HostKit.DSL.{Backup, ConfigFile, EnvFile, Ingress, Lifecycle, Readiness, Scope}
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

  defdirective roots(values) do
    Enum.each(values, fn {name, path} -> Scope.put_root(name, path) end)
  end

  defdirective prefixes(values) do
    Enum.each(values, fn {name, prefix} ->
      Scope.put_prefix(name, prefix)
    end)
  end

  defblock provider(name, module) do
    start(Scope.start_provider_config(name, module))
    finish(Scope.finish_provider_config())
  end

  defdirective set(key, value) do
    cond do
      EnvFile.Scope.active?() ->
        EnvFile.Scope.put_set(key, value)

      ConfigFile.Scope.active?() ->
        ConfigFile.Scope.put_set(key, value)

      true ->
        Scope.put_provider_config(key, value)
    end
  end

  defblock dotenv(path, opts \\ []) do
    start(EnvFile.Scope.start(path, opts))
    finish(Scope.add_resource(EnvFile.Scope.finish()))
  end

  defblock env_file(path, opts \\ []) do
    start(EnvFile.Scope.start(path, opts))
    finish(Scope.add_resource(EnvFile.Scope.finish()))
  end

  defblock env(name, opts \\ []) do
    start do
      env_path = Scope.env_path(name, opts)

      env_opts =
        opts
        |> Keyword.put_new(:owner, "root")
        |> Keyword.put_new(:group, service_user())

      EnvFile.Scope.start(env_path, env_opts)
    end

    finish do
      Scope.put_env(name, env_path)
      Scope.add_resource(EnvFile.Scope.finish())
    end
  end

  defdirective env(name) do
    path = Scope.env_path!(name)
    SystemdScope.put_service(:environment_file, path)
    path
  end

  defblock backup(opts \\ []) do
    start(Backup.Scope.start(opts))
    finish(Backup.Scope.finish())
  end

  defdirective include(value) do
    Backup.Scope.include(value)
  end

  defdirective include(value, opts) do
    Backup.Scope.include(value, opts)
  end

  defdirective consistency(strategy) do
    Backup.Scope.consistency(strategy)
  end

  defdirective verify(path) do
    Backup.Scope.verify(path)
  end

  defdirective verify(path, member) do
    Backup.Scope.verify(path, member)
  end

  defdirective keep(opts) do
    Backup.Scope.keep(opts)
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

  defdirective tls(mode, opts \\ []), source: true do
    if Scope.proxy_service_active?() do
      Scope.put_proxy_tls(mode)
    else
      Ingress.Scope.put_tls(mode, opts, source)
    end
  end

  defblock route(opts), source: true do
    start(Ingress.Scope.start_route(opts, source))
    finish(Ingress.Scope.finish_route())
  end

  defdirective proxy(opts), source: true do
    Ingress.Scope.put_proxy(opts, source)
  end

  defdirective systemd(unit, opts \\ []), source: true do
    Readiness.Scope.add_check(Readiness.Scope.systemd_check(unit, opts, source))
  end

  defdirective http(url_or_opts \\ []), source: true do
    cond do
      Readiness.Scope.active?() ->
        Readiness.Scope.add_check(Readiness.Scope.http_check(url_or_opts, [], source))

      Scope.proxy_active?() ->
        Scope.put_proxy_listener(:http, url_or_opts)

      true ->
        raise ArgumentError, "http/1 is only supported inside ready/2 or proxy/3"
    end
  end

  defdirective http(url, opts), source: true do
    cond do
      Readiness.Scope.active?() ->
        Readiness.Scope.add_check(Readiness.Scope.http_check(url, opts, source))

      Scope.proxy_active?() ->
        raise ArgumentError, "proxy http listener expects keyword options, got two arguments"

      true ->
        raise ArgumentError, "http/2 is only supported inside ready/2"
    end
  end

  defdirective https(opts \\ []) do
    Scope.put_proxy_listener(:https, opts)
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

  defdirective secret(key, opts) do
    if ConfigFile.Scope.active?() do
      ConfigFile.Scope.put_secret(key, opts)
    else
      EnvFile.Scope.put_secret(key, opts)
    end
  end

  defblock tenant(name, opts \\ []) do
    start do
      Scope.put_tenant(name, opts)
      Scope.start_workspace(name, Keyword.put_new(opts, :owner, name))
    end

    finish(Scope.finish_workspace())
  end

  defdirective host(name) do
    if Scope.proxy_active?() do
      Scope.add_proxy_host(name)
    else
      raise ArgumentError, "host/1 without a block is only supported inside proxy/3"
    end
  end

  defblock host(name) do
    start(Scope.start_host(name, []))
    finish(Scope.finish_host())
  end

  defblock host(name, opts) do
    start(Scope.start_host(name, opts))
    finish(Scope.finish_host())
  end

  defblock(instance(name, opts \\ [])) do
    start(Scope.start_instance(name, opts))
    finish(Scope.finish_instance())
  end

  defdirective backend(name) do
    Scope.put_instance_backend(name)
  end

  defblock backend(name) do
    start(Scope.start_backend_config(name))
    finish(Scope.finish_backend_config())
  end

  defdirective backend(name, opts) when is_list(opts) do
    Scope.put_instance_backend(name, opts)
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

  defdirective expose(name, opts \\ []) do
    if Scope.rpc_active?() do
      Scope.put_rpc_exposure(name, opts)
    else
      Scope.add_instance_port(name, opts)
    end
  end

  defblock proxy(name, opts), source: true do
    start(Scope.start_proxy(name, opts, source))
    finish(Scope.finish_proxy())
  end

  defblock service(name, opts \\ []) do
    start do
      if Scope.proxy_active?() do
        Scope.start_proxy_service(name, opts)
      else
        Scope.start_service(name, opts)
      end
    end

    finish do
      if Scope.proxy_service_active?() do
        Scope.finish_proxy_service()
      else
        Scope.finish_service()
      end
    end
  end

  defblock(workspace(name, opts)) do
    start(Scope.start_workspace(name, opts))
    finish(Scope.finish_workspace())
  end

  defdirective put_in_meta(key, value) do
    Scope.update_current(:service, &put_in(&1.meta[key], value))
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

  defblock ssh(), optional: true do
    start(Scope.start_ssh([]))
    finish(Scope.finish_ssh())
  end

  defblock ssh(opts), optional: true do
    start(Scope.start_ssh(opts))
    finish(Scope.finish_ssh())
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

  defdirective secret_env(name) do
    HostKit.Secret.env(name)
  end

  defblock(observability()) do
    start(Scope.start_observability())
    finish(Scope.finish_observability())
  end

  defblock firewall(opts \\ []), source: true do
    start(Scope.start_firewall(opts, source))
    finish(Scope.finish_firewall())
  end

  defdirective allow(opts) do
    Scope.add_firewall_rule(HostKit.Firewall.allow(opts))
  end

  defdirective deny(target, opts \\ []) do
    Scope.add_firewall_rule(HostKit.Firewall.deny(target, opts))
  end

  defdirective egress(opts) do
    user = service_user()
    policy = HostKit.Workspace.Egress.new(Keyword.put_new(opts, :user, user))
    Scope.update_current(:service, &put_in(&1.meta[:egress], policy))
  end

  defblock rpc() do
    start(Scope.start_rpc())
    finish(Scope.finish_rpc())
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

  defdirective agent(opts \\ []) do
    service Keyword.get(opts, :service, :agent) do
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
          exec_start: Keyword.get(opts, :exec_start, ["/usr/local/bin/hostkit-workspace-agent"])
        )

        restart(:on_failure)
        wanted_by(:multi_user)
        listen(:agent, port: Keyword.get(opts, :port, 4173), on: :loopback)

        put_in_meta(
          :agent_socket,
          Keyword.get(opts, :socket, "/run/hostkit/workspaces/#{service_user()}.sock")
        )

        logs(identifier: service_user(), stdout: :journal, stderr: :journal)
        telemetry(logs: true, metrics: true, service_name: service_user())
        monitor(:systemd, expect: [state: :active], severity: :critical)
        network_policy(deny: :all, allow: [:loopback])
      end
    end
  end

  defdirective workspace_agent(opts \\ []) do
    agent(opts)
  end

  defdirective telemetry(opts) do
    if Scope.observability_active?() do
      Scope.put_observability(:telemetry, HostKit.Telemetry.config(opts))
    else
      HostKit.DSL.attach_telemetry(opts)
    end
  end

  defdirective logs(opts) do
    if Scope.observability_active?() do
      Scope.put_observability(:logs, HostKit.Logs.config(opts))
    else
      HostKit.DSL.attach_logs(opts)
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

  defdirective writable(name) when is_atom(name) do
    SystemdScope.put_isolation_sandbox(
      :read_write_paths,
      Scope.storage_path(name)
    )
  end

  defdirective writable(path) do
    SystemdScope.put_isolation_sandbox(:read_write_paths, path)
  end

  defdirective(private_network(value)) do
    SystemdScope.put_isolation_sandbox(:private_network, value)
  end

  defdirective network(:loopback) do
    SystemdScope.put_isolation_network(:loopback)
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

  defdirective preview(name, opts) do
    listen(name,
      port: Keyword.fetch!(opts, :port),
      on: Keyword.get(opts, :on, :loopback)
    )

    caddy_site name, Keyword.fetch!(opts, :domain) do
      reverse_proxy(listener(name))

      monitor(:http,
        url: "https://#{Keyword.fetch!(opts, :domain)}",
        expect: [status: Keyword.get(opts, :status, 200)]
      )

      telemetry(logs: true, metrics: :http, service_name: to_string(name))
      logs(driver: :caddy_access, format: :json, ship: true)
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

  defdirective monitor(type, opts \\ []) do
    cond do
      Scope.inside_active?() ->
        Scope.add_inside_monitor(type, opts)

      SystemdScope.active?() ->
        SystemdScope.put_monitor(type, opts)

      Code.ensure_loaded?(CaddyScope) and
          CaddyScope.active?() ->
        CaddyScope.put_monitor(type, opts)

      true ->
        Scope.update_last_resource(fn resource ->
          resource_id = HostKit.Resource.id(resource)

          check =
            HostKit.Monitor.check(
              type,
              Keyword.put(opts, :resource_id, resource_id)
            )

          update_in(resource.meta[:monitor], &(List.wrap(&1) ++ [check]))
        end)
    end
  end

  defdirective account(opts) when is_list(opts) do
    account(service_user(), opts)
  end

  defdirective account(name) do
    HostKit.Account.ref(name)
  end

  defdirective account(name, opts) do
    account_name = HostKit.Account.name!(name)

    Scope.add_resource(%Resources.Account{
      name: account_name,
      system: Keyword.get(opts, :system, false),
      home: Keyword.get(opts, :home),
      shell: Keyword.get(opts, :shell, "/usr/sbin/nologin"),
      groups: Keyword.get(opts, :groups, []),
      rollback: Keyword.get(opts, :rollback, :keep),
      meta: Keyword.get(opts, :meta, %{})
    })

    if Scope.service_active?() do
      Scope.put_service_account(account_name)
    end
  end

  defdirective(directory(path, opts \\ [])) do
    Scope.add_resource(Resources.Directory.new(path, opts))
  end

  defdirective endpoint(name_or_service, name_or_opts \\ :default, opts \\ []),
    source: HostKit.SourceLocation do
    if Scope.service_active?() and is_list(name_or_opts) and opts == [] do
      declaration_opts = HostKit.DSL.put_source_meta(name_or_opts, source)
      Scope.put_endpoint(name_or_service, declaration_opts)
    else
      ref_opts = HostKit.DSL.put_source_meta(opts, source)
      HostKit.Endpoint.new(name_or_service, name_or_opts, ref_opts)
    end
  end

  defdirective source(name, opts), source: HostKit.SourceLocation do
    resource_opts = put_source_meta(opts, source)
    Scope.add_resource(Resources.Source.new(name, resource_opts))
  end

  def put_source_meta(opts, source) do
    Keyword.update(opts, :meta, %{source: source}, &Map.put(&1, :source, source))
  end

  defdirective package(name, opts \\ []), source: HostKit.SourceLocation do
    package_opts = put_source_meta(opts, source)
    Scope.add_resource(Resources.Package.new(name, package_opts))
  end

  defdirective(packages(names, opts \\ [])) do
    Enum.each(names, &package(&1, opts))
  end

  defdirective(file(path, opts \\ [])) do
    Scope.add_resource(Resources.File.new(path, opts))
  end

  defdirective template(path, opts), source: HostKit.SourceLocation do
    template_opts =
      Keyword.put_new(opts, :base_dir, source.file |> Path.dirname() |> Path.expand())

    Scope.add_resource(Resources.Template.new(path, template_opts))
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

  defdirective exs(path, opts \\ []), quoted: [:block] do
    Scope.add_resource(Resources.Exs.new(path, block, opts))
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

  defdirective command(name, opts), source: HostKit.SourceLocation do
    command_opts = put_source_meta(opts, source)
    Scope.add_resource(Resources.Command.new(name, command_opts))
  end

  defdirective run(name, command, opts \\ []) do
    command(name, Keyword.put(opts, :exec, command))
  end

  defdirective git(name, command, opts \\ []) do
    command(
      name,
      Keyword.put(opts, :exec, HostKit.DSL.git_exec(command))
    )
  end

  defdirective bash(name, script, opts \\ []), source: HostKit.SourceLocation do
    shell_opts = put_source_meta(opts, source)
    Scope.add_resource(Resources.Shell.new(name, script, shell_opts))
  end

  defdirective(argv(command, opts \\ [])) do
    HostKit.CommandLine.argv(command, opts)
  end

  defdirective mix(task, opts \\ []) do
    mix_opts = Keyword.put_new(opts, :command, path(:bin, "mix"))
    HostKit.CommandLine.mix(task, mix_opts)
  end

  defdirective elixir(opts \\ []) do
    elixir_opts = Keyword.put_new(opts, :command, path(:bin, "elixir"))
    HostKit.CommandLine.elixir(elixir_opts)
  end

  defdirective elixir(script_or_args, opts) do
    elixir_opts = Keyword.put_new(opts, :command, path(:bin, "elixir"))
    HostKit.CommandLine.elixir(script_or_args, elixir_opts)
  end

  defdirective eval(expression, opts \\ []), quoted: [:expression] do
    eval_expression =
      case expression do
        expression when is_binary(expression) -> expression
        expression -> Macro.to_string(expression)
      end

    eval_opts = Keyword.put_new(opts, :command, path(:bin, "elixir"))

    if Lifecycle.Scope.active?() do
      Lifecycle.Scope.put_exec(Lifecycle.Scope.eval_exec(eval_expression, eval_opts))
    else
      HostKit.CommandLine.eval(eval_expression, eval_opts)
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
