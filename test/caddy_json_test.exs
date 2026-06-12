defmodule HostKit.CaddyJSONTest do
  use ExUnit.Case, async: true

  alias HostKit.Caddy.Directive.{Encode, FileServer, ReverseProxy, Root}
  alias HostKit.Caddy.Site

  test "builds Caddy JSON config structs for reverse proxy sites" do
    site = %Site{
      name: :search,
      host: "search.elixir.toys",
      directives: [%Encode{formats: [:zstd, :gzip]}, %ReverseProxy{upstreams: ["127.0.0.1:4200"]}]
    }

    config = HostKit.Caddy.JSON.config_for_sites([site])
    map = HostKit.Caddy.JSON.to_map(config)

    assert get_in(map, [
             "apps",
             "http",
             "servers",
             "srv0",
             "routes",
             Access.at(0),
             "match",
             Access.at(0),
             "host"
           ]) == [
             "search.elixir.toys"
           ]

    assert [subroute] =
             get_in(map, ["apps", "http", "servers", "srv0", "routes", Access.at(0), "handle"])

    handlers = get_in(subroute, ["routes", Access.at(0), "handle"])

    assert %{"handler" => "encode", "encodings" => %{"gzip" => %{}, "zstd" => %{}}} in handlers

    assert %{
             "handler" => "reverse_proxy",
             "upstreams" => [%{"dial" => "127.0.0.1:4200"}]
           } in handlers
  end

  test "builds Caddy JSON config structs for static sites" do
    site = %Site{
      name: :landing,
      host: "elixir.toys",
      directives: [
        %Root{path: "/srv/toys/www/elixir.toys"},
        %Encode{formats: [:zstd, :gzip]},
        %FileServer{}
      ]
    }

    map = [site] |> HostKit.Caddy.JSON.config_for_sites() |> HostKit.Caddy.JSON.to_map()

    handlers =
      get_in(map, [
        "apps",
        "http",
        "servers",
        "srv0",
        "routes",
        Access.at(0),
        "handle",
        Access.at(0),
        "routes",
        Access.at(0),
        "handle"
      ])

    assert %{"handler" => "vars", "root" => "/srv/toys/www/elixir.toys"} in handlers
    assert %{"browse" => nil, "handler" => "file_server"} in handlers
  end
end
