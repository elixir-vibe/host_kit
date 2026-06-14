defmodule HostKit.DSL do
  @moduledoc """
  Core HostKit DSL.

  The DSL is only a builder: it evaluates `.exs` declarations into plain HostKit
  structs and does not apply changes to the host.
  """

  defmacro __using__(opts) do
    plugins =
      opts
      |> Keyword.get(:providers, Keyword.get(opts, :plugins, []))
      |> Enum.map(&Macro.expand(&1, __CALLER__))
      |> HostKit.Provider.resolve()

    recipes =
      opts
      |> Keyword.get(:recipes, [])
      |> Enum.map(&Macro.expand(&1, __CALLER__))

    import_sigils? = Keyword.get(opts, :sigils, true)

    provider_imports =
      plugins
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
      HostKit.DSL.Scope.put_default_providers(unquote(plugins))
      import HostKit.DSL
      import HostKit.DSL.Systemd
      unquote(sigil_import)
      unquote_splicing(provider_imports)
      unquote_splicing(recipe_imports)
    end
  end

  defmacro project(name, opts \\ [], do: block) do
    quote do
      HostKit.DSL.Scope.start_project(unquote(name), unquote(opts))
      unquote(block)
      HostKit.DSL.Scope.finish_project()
    end
  end

  defmacro providers(providers) do
    quote do
      HostKit.DSL.Scope.put_providers(unquote(providers))
    end
  end

  defmacro roots(values) do
    quote do
      Enum.each(unquote(values), fn {name, path} -> HostKit.DSL.Scope.put_root(name, path) end)
    end
  end

  defmacro prefixes(values) do
    quote do
      Enum.each(unquote(values), fn {name, prefix} ->
        HostKit.DSL.Scope.put_prefix(name, prefix)
      end)
    end
  end

  defmacro provider(name, module, do: block) do
    quote do
      HostKit.DSL.Scope.start_provider_config(unquote(name), unquote(module))
      unquote(block)
      HostKit.DSL.Scope.finish_provider_config()
    end
  end

  defmacro set(key, value) do
    quote do
      if HostKit.DSL.EnvFile.Scope.active?() do
        HostKit.DSL.EnvFile.Scope.put_set(unquote(key), unquote(value))
      else
        HostKit.DSL.Scope.put_provider_config(unquote(key), unquote(value))
      end
    end
  end

  defmacro env_file(path, opts \\ [], do: block) do
    quote do
      HostKit.DSL.EnvFile.Scope.start(unquote(path), unquote(opts))
      unquote(block)
      HostKit.DSL.Scope.add_resource(HostKit.DSL.EnvFile.Scope.finish())
    end
  end

  defmacro ready(name, opts \\ [], do: block) do
    quote do
      HostKit.DSL.Readiness.Scope.start(unquote(name), unquote(opts))
      unquote(block)
      HostKit.DSL.Scope.add_resource(HostKit.DSL.Readiness.Scope.finish())
    end
  end

  defmacro ingress(name, opts \\ [], do: block) do
    quote do
      HostKit.DSL.Ingress.Scope.start_ingress(unquote(name), unquote(opts))
      unquote(block)
      HostKit.DSL.Scope.add_resource(HostKit.DSL.Ingress.Scope.finish_ingress())
    end
  end

  defmacro server(listen \\ ":443", opts \\ [], do: block) do
    quote do
      HostKit.DSL.Ingress.Scope.start_server(unquote(listen), unquote(opts))
      unquote(block)
      HostKit.DSL.Ingress.Scope.finish_server()
    end
  end

  defmacro tls(mode, opts \\ []) do
    quote do
      if HostKit.DSL.Scope.proxy_service_active?() do
        HostKit.DSL.Scope.put_proxy_tls(unquote(mode))
      else
        HostKit.DSL.Ingress.Scope.put_tls(unquote(mode), unquote(opts))
      end
    end
  end

  defmacro route(opts, do: block) do
    quote do
      HostKit.DSL.Ingress.Scope.start_route(unquote(opts))
      unquote(block)
      HostKit.DSL.Ingress.Scope.finish_route()
    end
  end

  defmacro proxy(opts) do
    quote do
      HostKit.DSL.Ingress.Scope.put_proxy(unquote(opts))
    end
  end

  defmacro systemd(unit, opts \\ []) do
    quote do
      HostKit.DSL.Readiness.Scope.add_check(
        HostKit.Readiness.Systemd.new(unquote(unit), unquote(opts))
      )
    end
  end

  defmacro http(url_or_opts \\ []) do
    quote do
      cond do
        HostKit.DSL.Readiness.Scope.active?() ->
          HostKit.DSL.Readiness.Scope.add_check(
            HostKit.Readiness.HTTP.new(unquote(url_or_opts), [])
          )

        HostKit.DSL.Scope.proxy_active?() ->
          HostKit.DSL.Scope.put_proxy_listener(:http, unquote(url_or_opts))

        true ->
          raise ArgumentError, "http/1 is only supported inside ready/2 or proxy/3"
      end
    end
  end

  defmacro http(url, opts) do
    quote do
      cond do
        HostKit.DSL.Readiness.Scope.active?() ->
          HostKit.DSL.Readiness.Scope.add_check(
            HostKit.Readiness.HTTP.new(unquote(url), unquote(opts))
          )

        HostKit.DSL.Scope.proxy_active?() ->
          raise ArgumentError, "proxy http listener expects keyword options, got two arguments"

        true ->
          raise ArgumentError, "http/2 is only supported inside ready/2"
      end
    end
  end

  defmacro https(opts \\ []) do
    quote do
      HostKit.DSL.Scope.put_proxy_listener(:https, unquote(opts))
    end
  end

  defmacro state(path) do
    quote do
      HostKit.DSL.Scope.put_proxy_state(unquote(path))
    end
  end

  defmacro acme(opts) do
    quote do
      HostKit.DSL.Scope.put_proxy_acme(unquote(opts))
    end
  end

  defmacro balance(policy, opts \\ []) do
    quote do
      HostKit.DSL.Scope.put_proxy_balance(unquote(policy), unquote(opts))
    end
  end

  defmacro health(path, opts \\ []) do
    quote do
      HostKit.DSL.Scope.put_proxy_health(unquote(path), unquote(opts))
    end
  end

  defmacro drain(timeout) do
    quote do
      HostKit.DSL.Scope.put_proxy_drain(unquote(timeout))
    end
  end

  defmacro secret(key, opts) do
    quote do
      HostKit.DSL.EnvFile.Scope.put_secret(unquote(key), unquote(opts))
    end
  end

  defmacro plugins(plugins) do
    quote do
      HostKit.DSL.Scope.put_providers(unquote(plugins))
    end
  end

  defmacro tenant(name, opts \\ [], do: block) do
    quote do
      HostKit.DSL.Scope.put_tenant(unquote(name), unquote(opts))

      workspace unquote(name), Keyword.put_new(unquote(opts), :owner, unquote(name)) do
        unquote(block)
      end
    end
  end

  defmacro host(name, opts \\ []) do
    case Keyword.pop(opts, :do) do
      {nil, _opts} ->
        quote do
          if HostKit.DSL.Scope.proxy_active?() do
            HostKit.DSL.Scope.add_proxy_host(unquote(name))
          else
            raise ArgumentError, "host/2 without a block is only supported inside proxy/3"
          end
        end

      {block, opts} ->
        quote do
          HostKit.DSL.Scope.start_host(unquote(name), unquote(opts))
          unquote(block)
          HostKit.DSL.Scope.finish_host()
        end
    end
  end

  defmacro host(name, opts, do: block) do
    quote do
      HostKit.DSL.Scope.start_host(unquote(name), unquote(opts))
      unquote(block)
      HostKit.DSL.Scope.finish_host()
    end
  end

  defmacro proxy(name, opts, do: block) do
    quote do
      HostKit.DSL.Scope.start_proxy(unquote(name), unquote(opts))
      unquote(block)
      HostKit.DSL.Scope.finish_proxy()
    end
  end

  defmacro service(name, opts \\ [], do: block) do
    quote do
      if HostKit.DSL.Scope.proxy_active?() do
        HostKit.DSL.Scope.start_proxy_service(unquote(name), unquote(opts))
        unquote(block)
        HostKit.DSL.Scope.finish_proxy_service()
      else
        HostKit.DSL.Scope.start_service(unquote(name), unquote(opts))
        unquote(block)
        HostKit.DSL.Scope.finish_service()
      end
    end
  end

  defmacro workspace(name, opts, do: block) do
    quote do
      HostKit.DSL.Scope.start_workspace(unquote(name), unquote(opts))
      unquote(block)
      HostKit.DSL.Scope.finish_workspace()
    end
  end

  defmacro path_name(value) do
    quote do
      HostKit.DSL.Scope.set_service_path_name(unquote(value))
    end
  end

  defmacro put_in_meta(key, value) do
    quote do
      HostKit.DSL.Scope.update_current(:service, &put_in(&1.meta[unquote(key)], unquote(value)))
    end
  end

  defmacro service_name do
    quote do
      HostKit.DSL.Scope.service_name()
    end
  end

  defmacro service_user do
    quote do
      HostKit.DSL.Scope.service_user()
    end
  end

  defmacro unit_name(suffix \\ ".service") do
    quote do
      HostKit.DSL.Scope.unit_name(unquote(suffix))
    end
  end

  defmacro root_path(root, child \\ nil) do
    quote do
      HostKit.DSL.Scope.root_path(unquote(root), unquote(child))
    end
  end

  defmacro storage(name, opts) do
    quote do
      HostKit.DSL.Scope.put_storage(unquote(name), unquote(opts))
    end
  end

  defmacro storage_volume(name) do
    quote do
      HostKit.DSL.Scope.storage_volume(unquote(name))
    end
  end

  defmacro storage_path(name) do
    quote do
      HostKit.DSL.Scope.storage_path(unquote(name))
    end
  end

  defmacro writable_storage_paths do
    quote do
      HostKit.DSL.Scope.writable_storage_paths()
    end
  end

  defmacro backup_storage do
    quote do
      HostKit.DSL.Scope.backup_storage()
    end
  end

  defmacro target(name, opts) do
    quote do
      HostKit.DSL.Scope.add_proxy_target(unquote(name), unquote(opts))
    end
  end

  defmacro hostname(value) do
    quote do
      HostKit.DSL.Scope.update_current(:host, &Map.put(&1, :hostname, unquote(value)))
    end
  end

  defmacro user(value) do
    quote do
      HostKit.DSL.Scope.update_current(:host, &Map.put(&1, :user, unquote(value)))
    end
  end

  defmacro sudo(value) do
    quote do
      HostKit.DSL.Scope.update_current(:host, &Map.put(&1, :sudo, unquote(value)))
    end
  end

  defmacro ssh(opts) do
    quote do
      HostKit.DSL.Scope.update_current(:host, fn host ->
        update_in(host.meta[:ssh], &Keyword.merge(&1 || [], unquote(opts)))
      end)
    end
  end

  defmacro secret_env(name) do
    quote do
      HostKit.Secret.env(unquote(name))
    end
  end

  defmacro observability(do: block) do
    quote do
      HostKit.DSL.Scope.start_observability()
      unquote(block)
      HostKit.DSL.Scope.finish_observability()
    end
  end

  defmacro firewall(opts \\ [], do: block) do
    quote do
      HostKit.DSL.Scope.start_firewall(unquote(opts))
      unquote(block)
      HostKit.DSL.Scope.finish_firewall()
    end
  end

  defmacro allow(opts) do
    quote do
      HostKit.DSL.Scope.add_firewall_rule(HostKit.Firewall.allow(unquote(opts)))
    end
  end

  defmacro deny(target, opts \\ []) do
    quote do
      HostKit.DSL.Scope.add_firewall_rule(HostKit.Firewall.deny(unquote(target), unquote(opts)))
    end
  end

  defmacro egress(opts) do
    quote do
      user = service_user()
      policy = HostKit.Workspace.Egress.new(Keyword.put_new(unquote(opts), :user, user))
      HostKit.DSL.Scope.update_current(:service, &put_in(&1.meta[:egress], policy))
    end
  end

  defmacro inside(do: block) do
    quote do
      HostKit.DSL.Scope.start_inside()
      unquote(block)
      HostKit.DSL.Scope.finish_inside()
    end
  end

  defmacro inside_monitor(type, opts \\ []) do
    quote do
      HostKit.DSL.Scope.add_inside_monitor(unquote(type), unquote(opts))
    end
  end

  defmacro agent(opts \\ []) do
    quote do
      service Keyword.get(unquote(opts), :service, :agent) do
        account(service_user(), system: true)

        directory(root_path(:data),
          owner: service_user(),
          group: service_user(),
          mode: :private_dir
        )

        daemon unit_name() do
          service_user(service_user())
          service_group(service_user())
          working_directory(root_path(:data))

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
      if HostKit.DSL.Scope.observability_active?() do
        HostKit.DSL.Scope.put_observability(:telemetry, HostKit.Telemetry.config(unquote(opts)))
      else
        HostKit.DSL.attach_telemetry(unquote(opts))
      end
    end
  end

  defmacro logs(opts) do
    quote do
      if HostKit.DSL.Scope.observability_active?() do
        HostKit.DSL.Scope.put_observability(:logs, HostKit.Logs.config(unquote(opts)))
      else
        HostKit.DSL.attach_logs(unquote(opts))
      end
    end
  end

  def attach_telemetry(opts) do
    config = HostKit.Telemetry.config(opts)

    cond do
      HostKit.DSL.Systemd.Scope.active?() ->
        HostKit.DSL.Systemd.Scope.put_telemetry(config)

      Code.ensure_loaded?(HostKit.Providers.Caddy.Scope) and
          HostKit.Providers.Caddy.Scope.active?() ->
        HostKit.Providers.Caddy.Scope.put_telemetry(config)

      true ->
        HostKit.DSL.Scope.update_last_resource(&put_in(&1.meta[:telemetry], config))
    end
  end

  def attach_logs(opts) do
    config = HostKit.Logs.config(opts)

    cond do
      HostKit.DSL.Systemd.Scope.active?() ->
        HostKit.DSL.Systemd.Scope.put_logs(config)

      Code.ensure_loaded?(HostKit.Providers.Caddy.Scope) and
          HostKit.Providers.Caddy.Scope.active?() ->
        HostKit.Providers.Caddy.Scope.put_logs(config)

      true ->
        HostKit.DSL.Scope.update_last_resource(&put_in(&1.meta[:logs], config))
    end
  end

  defmacro sandbox(profile, opts \\ []) do
    quote do
      HostKit.DSL.Systemd.Scope.apply_sandbox(unquote(profile), unquote(opts))
    end
  end

  defmacro network_policy(opts) do
    quote do
      HostKit.DSL.Systemd.Scope.put_network_policy(unquote(opts))
    end
  end

  defmacro listen(name_or_port, opts \\ []) do
    quote do
      HostKit.DSL.attach_listener(unquote(name_or_port), unquote(opts))
    end
  end

  defmacro listener(name) do
    quote do
      HostKit.DSL.Scope.listener_upstream(unquote(name))
    end
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
    listener = HostKit.DSL.Scope.put_listener(name, opts)

    if HostKit.DSL.Systemd.Scope.active?() do
      HostKit.DSL.Systemd.Scope.put_listen(listener.port, on: listener.on)
    end

    listener
  end

  def attach_listener(port, opts) when is_integer(port) do
    HostKit.DSL.Systemd.Scope.put_listen(port, opts)
  end

  defmacro monitor(type, opts \\ []) do
    quote do
      cond do
        HostKit.DSL.Scope.inside_active?() ->
          HostKit.DSL.Scope.add_inside_monitor(unquote(type), unquote(opts))

        HostKit.DSL.Systemd.Scope.active?() ->
          HostKit.DSL.Systemd.Scope.put_monitor(unquote(type), unquote(opts))

        Code.ensure_loaded?(HostKit.Providers.Caddy.Scope) and
            HostKit.Providers.Caddy.Scope.active?() ->
          HostKit.Providers.Caddy.Scope.put_monitor(unquote(type), unquote(opts))

        true ->
          HostKit.DSL.Scope.update_last_resource(fn resource ->
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

  defmacro account(name) do
    quote do
      HostKit.Account.ref(unquote(name))
    end
  end

  defmacro account(name, opts) do
    quote do
      HostKit.DSL.Scope.add_resource(%HostKit.Resources.Account{
        name: HostKit.Account.name!(unquote(name)),
        system: Keyword.get(unquote(opts), :system, false),
        home: Keyword.get(unquote(opts), :home),
        shell: Keyword.get(unquote(opts), :shell, "/usr/sbin/nologin"),
        groups: Keyword.get(unquote(opts), :groups, []),
        meta: Keyword.get(unquote(opts), :meta, %{})
      })
    end
  end

  defmacro directory(path, opts \\ []) do
    quote do
      HostKit.DSL.Scope.add_resource(
        HostKit.Resources.Directory.new(unquote(path), unquote(opts))
      )
    end
  end

  defmacro source_ref(name) do
    quote do
      HostKit.Source.Ref.new(unquote(name))
    end
  end

  defmacro endpoint(name_or_service, name_or_opts \\ :default, opts \\ []) do
    source = HostKit.SourceLocation.from_caller(__CALLER__)

    quote do
      if HostKit.DSL.Scope.service_active?() and is_list(unquote(name_or_opts)) and
           unquote(opts) == [] do
        declaration_opts =
          HostKit.DSL.put_source_meta(unquote(name_or_opts), unquote(Macro.escape(source)))

        HostKit.DSL.Scope.put_endpoint(unquote(name_or_service), declaration_opts)
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

      HostKit.DSL.Scope.add_resource(HostKit.Resources.Source.new(unquote(name), opts))
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

      HostKit.DSL.Scope.add_resource(HostKit.Resources.Package.new(unquote(name), opts))
    end
  end

  defmacro packages(names, opts \\ []) do
    quote do
      Enum.each(unquote(names), &package(&1, unquote(opts)))
    end
  end

  defmacro file(path, opts \\ []) do
    quote do
      HostKit.DSL.Scope.add_resource(HostKit.Resources.File.new(unquote(path), unquote(opts)))
    end
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

      HostKit.DSL.Scope.add_resource(HostKit.Resources.Command.new(unquote(name), opts))
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

      HostKit.DSL.Scope.add_resource(
        HostKit.Resources.Shell.new(unquote(name), unquote(script), opts)
      )
    end
  end

  def git_exec(%HostKit.CommandLine{} = command), do: {"git", [command.command | command.args]}

  def git_exec(command) when is_binary(command),
    do: command |> HostKit.CommandLine.parse!() |> git_exec()

  def git_exec(args) when is_list(args), do: ["git" | args]

  defmacro mise(opts \\ [], do: block) do
    quote do
      HostKit.DSL.Scope.start_mise(unquote(opts))
      unquote(block)
      HostKit.DSL.Scope.finish_mise()
    end
  end

  defmacro tool(name, version, opts \\ []) do
    quote do
      HostKit.DSL.Scope.add_tool(unquote(name), unquote(version), unquote(opts))
    end
  end
end
