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
        mode: Keyword.get(unquote(opts), :mode)
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
        mode: Keyword.get(unquote(opts), :mode)
      })
    end
  end
end
