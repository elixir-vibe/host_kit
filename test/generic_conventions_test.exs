defmodule HostKit.GenericConventionsTest do
  use ExUnit.Case, async: true

  test "generic service conventions derive names, paths, and storage" do
    source = """
    use HostKit.DSL

    project :demo do
      roots data: "/srv/toys", config: "/etc/toys"
      prefixes user: "toys-", unit: "toys-"

      service :forgejo do
        system_user service_user(), home: root_path(:data)

        storage :repositories,
          under: :data,
          path: "repositories",
          mode: 0o750,
          backup: true

        storage :config,
          under: :config,
          owner: "root",
          group: service_user(),
          mode: 0o750,
          writable: false,
          secret: true

        systemd_service unit_name() do
          service user: service_user(), read_write_paths: writable_storage_paths()
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Resources.User{name: "toys-forgejo"}, &1)
           )

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Resources.Directory{path: "/srv/toys/forgejo/repositories"}, &1)
           )

    assert Enum.any?(
             service.resources,
             &match?(
               %HostKit.Resources.Directory{
                 path: "/etc/toys/forgejo",
                 owner: "root",
                 meta: %{secret: true}
               },
               &1
             )
           )

    assert Enum.any?(service.resources, fn
             %HostKit.Systemd.Service{name: "toys-forgejo.service", service: opts} ->
               opts[:user] == "toys-forgejo" and
                 opts[:read_write_paths] == ["/srv/toys/forgejo/repositories"]

             _resource ->
               false
           end)
  end
end
