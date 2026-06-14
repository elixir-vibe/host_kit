defmodule HostKit.CaddyStaticTest do
  use HostKit.Case, async: true

  test "renders static file server site" do
    project = HostKit.load!(fixture_path("caddy_static_project.hostkit"))

    assert {:ok, rendered} = HostKit.Render.render(project, {:caddy_site, :landing})

    route = rendered |> IO.iodata_to_binary() |> Jason.decode!()

    assert get_in(route, ["match", Access.at(0), "host"]) == ["elixir.toys"]

    assert [subroute] = route["handle"]
    handlers = get_in(subroute, ["routes", Access.at(0), "handle"])

    assert %{"handler" => "vars", "root" => "/srv/toys/www/elixir.toys"} in handlers
    assert %{"browse" => nil, "handler" => "file_server"} in handlers
  end
end
