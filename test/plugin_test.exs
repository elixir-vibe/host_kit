defmodule HostKit.PluginTest do
  use ExUnit.Case, async: true

  test "plugins can contribute DSL and renderers" do
    project = HostKit.load!(fixture_path("plugin_project.hostkit"))

    assert HostKit.TestPlugin in project.plugins
    assert [%HostKit.Service{resources: [%HostKit.TestSite{} = site]}] = project.services
    assert site.host == "example.test"
    assert site.upstream == "127.0.0.1:4000"

    assert {:ok, rendered} = HostKit.Render.render(project, {:test_site, "example.test"})
    assert IO.iodata_to_binary(rendered) == "example.test -> 127.0.0.1:4000\n"
  end

  defp fixture_path(name), do: Path.expand("fixtures/#{name}", __DIR__)
end
