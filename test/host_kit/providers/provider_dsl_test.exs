defmodule HostKit.ProviderTest do
  use HostKit.Case, async: true

  test "providers can contribute DSL and renderers" do
    project = HostKit.load!(fixture_path("plugin_project.hostkit"))

    assert HostKit.TestPlugin in project.providers
    assert [%HostKit.Service{resources: [%HostKit.TestSite{} = site]}] = project.services
    assert site.host == "example.test"
    assert site.upstream == "127.0.0.1:4000"

    assert {:ok, rendered} = HostKit.Render.render(project, {:test_site, "example.test"})
    assert IO.iodata_to_binary(rendered) == "example.test -> 127.0.0.1:4000\n"
  end
end
