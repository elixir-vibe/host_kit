defmodule HostKit.Examples.FullHostTest do
  use ExUnit.Case, async: true

  test "full host example stays loadable" do
    project = HostKit.load!("examples/full_host.exs")

    assert project.name == :prod
    assert HostKit.Providers.Caddy in project.providers
    assert [%HostKit.Host{name: :app}] = project.hosts
    assert Enum.map(project.services, & &1.name) == [:api]

    resources = HostKit.Project.resources(project)

    assert Enum.any?(resources, &match?(%HostKit.Resources.Mise{}, &1))
    assert Enum.any?(resources, &match?(%HostKit.Systemd.Service{name: "api.service"}, &1))
    assert Enum.any?(resources, &match?(%HostKit.Caddy.Site{name: "api.example.com"}, &1))
  end
end
