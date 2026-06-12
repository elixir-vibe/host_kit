defmodule HostKit.ProjectDSLTest do
  use ExUnit.Case, async: true

  test "project-local DSLs can define service conventions" do
    project = HostKit.load!(fixture_path("project_dsl.hostkit"))

    assert [service] = project.services
    assert service.name == :exograph

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Resources.User{name: "toys-exograph"}, &1)
           )

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Resources.Directory{path: "/srv/toys/exograph"}, &1)
           )

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Resources.Directory{path: "/var/lib/toys/exograph/home"}, &1)
           )

    assert Enum.any?(service.resources, fn
             %HostKit.Systemd.Service{name: "toys-exograph.service", service: service_opts} ->
               Keyword.fetch!(service_opts, :working_directory) == "/opt/toys/src/exograph" and
                 Keyword.fetch!(service_opts, :read_write_paths) == [
                   "/srv/toys/exograph",
                   "/var/lib/toys/exograph",
                   "/opt/toys/src/exograph"
                 ]

             _resource ->
               false
           end)
  end

  defp fixture_path(name), do: Path.expand("fixtures/#{name}", __DIR__)
end
