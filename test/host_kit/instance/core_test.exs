defmodule HostKit.InstanceTest do
  use ExUnit.Case, async: true

  test "instance declares backend lifecycle hosts and nested HostKit services" do
    source = """
    use HostKit.DSL, providers: [HostKit.Providers.Caddy]

    project :demo do
      instance :demo_vm do
        backend :incus
        image "images:ubuntu/24.04"
        kind :container
        lifecycle :ephemeral

        expose :ssh, host: 2222, guest: 22
        expose :web, host: 18080, guest: 80

        host :guest, at: "127.0.0.1" do
          ssh do
            user "root"
            password "hostkit-demo"
            port 2222
            accept_hosts true
          end
        end

        service :web do
          account system: true
          storage :www, path: "/srv/www", mode: 0o755

          file "/srv/www/index.html", content: "hello", mode: 0o644

          daemon do
            exec ["/usr/bin/env", "true"]

            isolate do
              writable :www
              network :loopback
            end

            listen :http, port: 80
          end

          caddy_site ":18080" do
            reverse_proxy :http
          end
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)

    assert [] = project.hosts
    assert [] = project.services
    assert [instance] = project.instances
    assert instance.name == :demo_vm
    assert instance.backend == :incus
    assert instance.image == "images:ubuntu/24.04"
    assert instance.kind == :container
    assert instance.lifecycle == :ephemeral

    assert instance.ports == [
             %{name: :ssh, host: 2222, guest: 22, protocol: :tcp},
             %{name: :web, host: 18_080, guest: 80, protocol: :tcp}
           ]

    assert [host] = instance.hosts
    assert host.name == :guest
    assert host.hostname == "127.0.0.1"
    assert host.user == "root"
    assert host.sudo == false
    assert host.meta.ssh[:password] == "hostkit-demo"
    assert host.meta.ssh[:port] == 2222
    assert host.meta.ssh[:silently_accept_hosts] == true

    assert [service] = instance.services
    assert service.name == :web

    assert Enum.any?(service.resources, &match?(%HostKit.Resources.Account{name: "web"}, &1))

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Resources.File{path: "/srv/www/index.html"}, &1)
           )

    assert %HostKit.Systemd.Service{} =
             unit = Enum.find(service.resources, &match?(%HostKit.Systemd.Service{}, &1))

    assert unit.name == "web.service"
    assert unit.service[:user] == "web"
    assert unit.service[:read_write_paths] == ["/srv/www"]
    assert unit.meta.listen == [%{port: 80, on: {127, 0, 0, 1}}]

    assert %HostKit.Caddy.Site{} =
             site = Enum.find(service.resources, &match?(%HostKit.Caddy.Site{}, &1))

    assert site.host == ":18080"
    assert [%HostKit.Caddy.Directive.ReverseProxy{upstreams: ["127.0.0.1:80"]}] = site.directives
  end
end
