defmodule HostKit.DSL.CoreTest do
  use ExUnit.Case, async: true

  test "declares host bootstrap service isolation env and Caddy proxy without repeated plumbing" do
    source = """
    use HostKit.DSL, providers: [HostKit.Providers.Caddy]

    project :prod do
      host :app, at: "app.example.com" do
        ssh do
          user "root"
          identity_file Path.expand("~/.ssh/id_ed25519")
          accept_hosts true
          retry attempts: 3
        end
      end

      bootstrap do
        package :ca_certificates

        mise do
          tool :erlang, "29.0.2"
          tool :elixir, "1.20.1"
        end
      end

      service :api do
        account system: true
        storage :data, mode: 0o750

        env :runtime do
          secret :database_url, env: "DATABASE_URL"
        end

        daemon do
          env :runtime
          exec ["/opt/api/bin/server"]

          isolate do
            memory_max "512M"
            writable :data
            network :loopback
          end

          listen :http, port: 4000
        end

        caddy_site "api.example.com" do
          reverse_proxy :http
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)

    assert [host] = project.hosts
    assert host.hostname == "app.example.com"
    assert host.user == "root"
    assert host.sudo == false
    assert host.meta.ssh[:identity_file] == Path.expand("~/.ssh/id_ed25519")
    assert host.meta.ssh[:silently_accept_hosts] == true
    assert host.meta.ssh[:retry] == [attempts: 3]

    assert Enum.any?(project.resources, &match?(%HostKit.Resources.Mise{}, &1))

    assert [service] = project.services
    assert service.name == :api

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Resources.Directory{path: "/var/lib/api"}, &1)
           )

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Resources.EnvFile{path: "/etc/api/runtime.env"}, &1)
           )

    assert %HostKit.Systemd.Service{} =
             unit =
             Enum.find(service.resources, &match?(%HostKit.Systemd.Service{}, &1))

    assert unit.name == "api.service"
    assert unit.install[:wanted_by] == "multi-user.target"
    assert unit.service[:user] == "api"
    assert unit.service[:group] == "api"
    assert unit.service[:environment_file] == "/etc/api/runtime.env"
    assert unit.service[:exec_start] == "/opt/api/bin/server"
    assert unit.service[:memory_max] == "512M"
    assert unit.service[:read_write_paths] == ["/var/lib/api"]
    assert unit.meta.network_policy == %{deny: :all, allow: [:loopback]}

    assert %HostKit.Caddy.Site{} =
             site =
             Enum.find(service.resources, &match?(%HostKit.Caddy.Site{}, &1))

    assert site.name == "api.example.com"

    assert [%HostKit.Caddy.Directive.ReverseProxy{upstreams: ["127.0.0.1:4000"]}] =
             site.directives
  end

  test "release emits inspectable version directory and current symlink" do
    source = """
    use HostKit.DSL

    project :prod do
      roots opt: "/opt/apps"

      service :gatus do
        release :gatus,
          version: "5.36.0",
          owner: "deploy",
          group: "deploy",
          current_dir: [owner: "deploy", group: "deploy"]

        file path(:opt, "current/gatus/VERSION"), content: "5.36.0"
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services

    assert [
             %HostKit.Resources.Directory{
               path: "/opt/apps/releases/gatus",
               owner: "deploy",
               group: "deploy",
               mode: 0o755
             },
             %HostKit.Resources.Directory{
               path: "/opt/apps/current",
               owner: "deploy",
               group: "deploy",
               mode: 0o755
             },
             %HostKit.Resources.Symlink{
               path: "/opt/apps/current/gatus",
               to: "/opt/apps/releases/gatus/5.36.0",
               owner: "root",
               group: "root"
             },
             %HostKit.Resources.File{
               path: "/opt/apps/current/gatus/VERSION",
               content: "5.36.0"
             }
           ] = service.resources
  end

  test "rpc exposes and binds service surfaces through unix socket listeners" do
    source = """
    use HostKit.DSL

    project :prod do
      roots run: "/run/apps", config: "/etc/apps"
      prefixes user: "app-", unit: "app-"

      service :catalog do
        account system: true

        daemon do
          listen :rpc, protocol: :rpc
        end

        rpc do
          expose :query
          expose :control
        end
      end

      service :web do
        account system: true
        bind :catalog, rpc: [:query]
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    [provider, caller] = project.services

    assert %HostKit.Listener{
             name: :rpc,
             protocol: :rpc,
             socket: "/run/apps/catalog/rpc.sock",
             port: nil,
             meta: %{socket_owner: "app-catalog", socket_group: "app-catalog", socket_mode: 0o660}
           } = provider.meta.listeners.rpc

    assert %HostKit.RPC{exposes: exposes, bindings: []} = provider.meta.rpc
    assert Enum.map(exposes, & &1.name) == [:query, :control]
    assert Enum.all?(exposes, &(&1.listener == :rpc))

    refute Enum.any?(
             provider.resources,
             &match?(%HostKit.Systemd.Service{service: %{listen_stream: _}}, &1)
           )

    resources = HostKit.Project.resources(project)

    assert %HostKit.Resources.Account{name: "app-web", groups: ["app-catalog"]} =
             Enum.find(resources, &match?(%HostKit.Resources.Account{name: "app-web"}, &1))

    assert %HostKit.RPC{exposes: [], bindings: [binding]} = caller.meta.rpc
    assert binding.service == :catalog
    assert binding.surfaces == [:query]
    assert binding.listener == :rpc

    assert %HostKit.Resources.File{path: "/etc/apps/web/rpc.exs", content: content} =
             rpc_file =
             Enum.find(
               resources,
               &match?(%HostKit.Resources.File{path: "/etc/apps/web/rpc.exs"}, &1)
             )

    assert rpc_file.group == "app-web"

    assert Code.eval_string(content) |> elem(0) == %{
             catalog: %{
               listener: :rpc,
               socket: "/run/apps/catalog/rpc.sock",
               upstream: "unix:/run/apps/catalog/rpc.sock",
               surfaces: [:query],
               unit: "app-catalog.service"
             }
           }
  end

  test "rpc bindings validate target services listeners and surfaces" do
    project =
      Code.eval_string("""
      use HostKit.DSL

      project :prod do
        service :catalog do
          daemon do
            listen :rpc, protocol: :rpc
          end

          rpc do
            expose :query
          end
        end

        service :web do
          bind :catalog, rpc: [:control]
          bind :missing, rpc: [:query]
        end
      end
      """)
      |> elem(0)

    assert {:error, diagnostics} = HostKit.plan(project)
    assert Enum.map(diagnostics.errors, & &1.code) == [:rpc_unknown_surface, :rpc_unknown_service]
  end

  test "non-rpc listeners still require ports" do
    assert_raise ArgumentError, ~r/http listener requires a port/, fn ->
      Code.eval_string("""
      use HostKit.DSL

      project :prod do
        service :api do
          daemon do
            listen :http
          end
        end
      end
      """)
    end
  end

  test "storage and env defaults use declared service roots" do
    source = """
    use HostKit.DSL

    project :prod do
      roots data: "/srv/apps", state: "/var/lib/apps", config: "/etc/apps"
      prefixes user: "app-", unit: "app-"

      service :api do
        account system: true
        storage :data, mode: 0o750
        storage :state, mode: 0o750

        env :runtime do
          set :mix_env, :prod
        end

        daemon do
          env :runtime
          exec ["/opt/apps/api/bin/server"]

          isolate do
            writable :data
            writable :state
          end
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Resources.Directory{path: "/srv/apps/api"}, &1)
           )

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Resources.Directory{path: "/var/lib/apps/api"}, &1)
           )

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Resources.EnvFile{path: "/etc/apps/api/runtime.env"}, &1)
           )

    unit = Enum.find(service.resources, &match?(%HostKit.Systemd.Service{}, &1))

    assert unit.name == "app-api.service"
    assert unit.service[:user] == "app-api"
    assert unit.service[:group] == "app-api"
    assert unit.service[:environment_file] == "/etc/apps/api/runtime.env"
    assert unit.service[:read_write_paths] == ["/srv/apps/api", "/var/lib/apps/api"]
  end
end
