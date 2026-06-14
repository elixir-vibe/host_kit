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
