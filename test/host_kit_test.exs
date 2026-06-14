defmodule HostKitTest do
  use ExUnit.Case, async: true

  test "DSL builds inspectable project structs" do
    path = fixture_path("project.hostkit")

    assert {:ok, project} = HostKit.load(path)
    assert project.name == :toys
    assert [%HostKit.Service{name: :exograph, resources: resources}] = project.services

    assert %HostKit.Resources.Account{name: "toys-exograph", system: true} = Enum.at(resources, 0)
    assert %HostKit.Resources.Directory{path: "/srv/toys/exograph"} = Enum.at(resources, 1)
    assert %HostKit.Systemd.Service{name: "toys-exograph.service"} = Enum.at(resources, 2)
  end

  test "plan summarizes resource kinds" do
    project = HostKit.load!(fixture_path("project.hostkit"))

    assert {:ok, plan} = HostKit.plan(project)
    assert plan.summary == %{account: 1, directory: 1, systemd_service: 1}
  end

  test "systemd resources render through core renderer" do
    project = HostKit.load!(fixture_path("project.hostkit"))

    assert {:ok, rendered} =
             HostKit.Render.render(project, {:systemd_service, "toys-exograph.service"})

    rendered = IO.iodata_to_binary(rendered)

    assert rendered =~ "[Unit]"
    assert rendered =~ "Description=Exograph search"
    assert rendered =~ "ExecStart=/usr/local/bin/mix exograph.index.hex --web --port 4200"
  end

  defp fixture_path(name), do: Path.expand("fixtures/#{name}", __DIR__)
end
