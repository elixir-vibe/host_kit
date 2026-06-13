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

    provider_imports =
      plugins
      |> HostKit.Provider.dsl_modules()
      |> Enum.map(fn dsl ->
        quote do
          import unquote(dsl)
        end
      end)

    quote do
      import HostKit.DSL
      import HostKit.DSL.Systemd
      unquote_splicing(provider_imports)
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

  defmacro host(name, opts \\ [], do: block) do
    quote do
      HostKit.DSL.Scope.start_host(unquote(name), unquote(opts))
      unquote(block)
      HostKit.DSL.Scope.finish_host()
    end
  end

  defmacro service(name, opts \\ [], do: block) do
    quote do
      HostKit.DSL.Scope.start_service(unquote(name), unquote(opts))
      unquote(block)
      HostKit.DSL.Scope.finish_service()
    end
  end

  defmacro path_name(value) do
    quote do
      HostKit.DSL.Scope.set_service_path_name(unquote(value))
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

  defmacro observability(do: block) do
    quote do
      HostKit.DSL.Scope.start_observability()
      unquote(block)
      HostKit.DSL.Scope.finish_observability()
    end
  end

  defmacro firewall(do: block) do
    quote do
      HostKit.DSL.Scope.start_firewall()
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

      Code.ensure_loaded?(HostKit.Plugins.Caddy.Scope) and HostKit.Plugins.Caddy.Scope.active?() ->
        HostKit.Plugins.Caddy.Scope.put_telemetry(config)

      true ->
        HostKit.DSL.Scope.update_last_resource(&put_in(&1.meta[:telemetry], config))
    end
  end

  def attach_logs(opts) do
    config = HostKit.Logs.config(opts)

    cond do
      HostKit.DSL.Systemd.Scope.active?() ->
        HostKit.DSL.Systemd.Scope.put_logs(config)

      Code.ensure_loaded?(HostKit.Plugins.Caddy.Scope) and HostKit.Plugins.Caddy.Scope.active?() ->
        HostKit.Plugins.Caddy.Scope.put_logs(config)

      true ->
        HostKit.DSL.Scope.update_last_resource(&put_in(&1.meta[:logs], config))
    end
  end

  defmacro network_policy(opts) do
    quote do
      HostKit.DSL.Systemd.Scope.put_network_policy(unquote(opts))
    end
  end

  defmacro listen(port, opts \\ []) do
    quote do
      HostKit.DSL.Systemd.Scope.put_listen(unquote(port), unquote(opts))
    end
  end

  defmacro monitor(type, opts \\ []) do
    quote do
      cond do
        HostKit.DSL.Systemd.Scope.active?() ->
          HostKit.DSL.Systemd.Scope.put_monitor(unquote(type), unquote(opts))

        Code.ensure_loaded?(HostKit.Plugins.Caddy.Scope) and HostKit.Plugins.Caddy.Scope.active?() ->
          HostKit.Plugins.Caddy.Scope.put_monitor(unquote(type), unquote(opts))

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

  defmacro system_user(name, opts \\ []) do
    quote do
      HostKit.DSL.Scope.add_resource(%HostKit.Resources.User{
        name: unquote(name),
        system: true,
        home: Keyword.get(unquote(opts), :home),
        shell: Keyword.get(unquote(opts), :shell, "/usr/sbin/nologin"),
        groups: Keyword.get(unquote(opts), :groups, [])
      })
    end
  end

  defmacro directory(path, opts \\ []) do
    quote do
      HostKit.DSL.Scope.add_resource(%HostKit.Resources.Directory{
        path: unquote(path),
        owner: Keyword.get(unquote(opts), :owner),
        group: Keyword.get(unquote(opts), :group),
        mode: HostKit.Mode.normalize!(Keyword.get(unquote(opts), :mode))
      })
    end
  end

  defmacro file(path, opts \\ []) do
    quote do
      HostKit.DSL.Scope.add_resource(%HostKit.Resources.File{
        path: unquote(path),
        content: Keyword.get(unquote(opts), :content),
        owner: Keyword.get(unquote(opts), :owner),
        group: Keyword.get(unquote(opts), :group),
        mode: HostKit.Mode.normalize!(Keyword.get(unquote(opts), :mode))
      })
    end
  end
end
