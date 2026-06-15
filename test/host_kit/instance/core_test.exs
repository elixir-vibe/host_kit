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
             %{name: :ssh, host: 2222, guest: 22, protocol: :tcp, bind: "127.0.0.1"},
             %{name: :web, host: 18_080, guest: 80, protocol: :tcp, bind: "127.0.0.1"}
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

    project_resources = HostKit.Project.resources(project)
    assert [%HostKit.Instance{name: :demo_vm} | nested_resources] = project_resources
    assert Enum.any?(nested_resources, &match?(%HostKit.Caddy.Site{}, &1))

    assert Enum.all?(nested_resources, fn resource ->
             resource.meta.instance == :demo_vm and
               resource.meta.host == :guest and
               resource.meta.target_opts[:reader] == HostKit.Remote
           end)
  end

  test "instance backend supports declarative backend options" do
    source = """
    use HostKit.DSL

    project :demo do
      instance :demo_vm do
        backend :incus, sudo: true, project: "hostkit", command: "incus"
        image "images:ubuntu/24.04"
      end

      instance :block_vm do
        backend :incus do
          option :sudo, true
          option :project, "hostkit"
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)

    assert [%HostKit.Instance{} = demo, %HostKit.Instance{} = block] = project.instances
    assert demo.backend == :incus
    assert demo.backend_config == %{sudo: true, project: "hostkit", command: "incus"}
    assert block.backend == :incus
    assert block.backend_config == %{sudo: true, project: "hostkit"}
  end

  test "instance target_host selects which nested host receives content resources" do
    source = """
    use HostKit.DSL

    project :demo do
      instance :demo_vm do
        backend :incus
        target_host :private

        host :public, at: "127.0.0.1" do
          ssh user: "root", port: 2222
        end

        host :private, at: "10.0.3.10" do
          ssh user: "ubuntu", port: 22
        end

        service :web do
          file "/srv/www/index.html", content: "hello"
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [%HostKit.Instance{target_host: :private}] = project.instances

    file = Enum.find(HostKit.Project.resources(project), &match?(%HostKit.Resources.File{}, &1))
    assert file.meta.instance == :demo_vm
    assert file.meta.host == :private
    assert file.meta.target_opts[:target].opts[:host] == "10.0.3.10"
    assert file.meta.target_opts[:target].opts[:user] == "ubuntu"
  end

  test "instance target_host must refer to a nested host" do
    project = %HostKit.Project{
      name: :demo,
      instances: [
        %HostKit.Instance{
          name: :demo_vm,
          target_host: :missing,
          resources: [%HostKit.Resources.File{path: "/tmp/demo", content: "demo"}]
        }
      ]
    }

    assert_raise ArgumentError, ~r/target_host :missing is not declared/, fn ->
      HostKit.Project.resources(project)
    end
  end

  test "persistent instances are skipped in down plans while ephemeral instances are destroyed last" do
    source = """
    use HostKit.DSL

    project :demo do
      instance :persistent_vm do
        backend :incus
        lifecycle :persistent
      end

      instance :ephemeral_vm do
        backend :incus
        lifecycle :ephemeral

        host :guest, at: "127.0.0.1" do
          ssh user: "root", port: 2222
        end

        service :web do
          file "/srv/www/index.html", content: "hello"
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert {:ok, plan} = HostKit.plan(project)
    assert {:ok, down} = HostKit.down(plan)

    assert Enum.any?(down.diagnostics.warnings, fn warning ->
             warning.resource_id == {:instance, :persistent_vm} and
               warning.details.reason == :delete_not_supported
           end)

    assert Enum.map(down.changes, & &1.resource_id) == [
             {:file, "/srv/www/index.html"},
             {:instance, :ephemeral_vm}
           ]
  end

  test "instances participate in project resources plans and ephemeral down plans" do
    source = """
    use HostKit.DSL

    project :demo do
      instance :demo_vm do
        backend :incus
        image "images:ubuntu/24.04"
        kind :container
        lifecycle :ephemeral
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)

    assert [%HostKit.Instance{name: :demo_vm}] = HostKit.Project.resources(project)
    assert {:ok, plan} = HostKit.plan(project)
    assert [%HostKit.Change{action: :create, resource_id: {:instance, :demo_vm}}] = plan.changes

    assert {:ok, [%{status: :dry_run}]} = HostKit.apply(plan, dry_run: true)

    assert {:ok, down} = HostKit.down(plan)
    assert [%HostKit.Change{action: :delete, resource_id: {:instance, :demo_vm}}] = down.changes
  end
end
