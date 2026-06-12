defmodule HostKit.CaddyStaticTest do
  use ExUnit.Case, async: true

  test "renders static file server site" do
    project = HostKit.load!(fixture_path("caddy_static_project.hostkit"))

    assert {:ok, rendered} = HostKit.Render.render(project, {:caddy_site, :landing})

    assert IO.iodata_to_binary(rendered) == """
           elixir.toys {
           \troot * /srv/toys/www/elixir.toys
           \tencode zstd gzip
           \tfile_server
           }
           """
  end

  defp fixture_path(name), do: Path.expand("fixtures/#{name}", __DIR__)
end
