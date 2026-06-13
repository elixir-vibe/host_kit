defmodule HostKit.CaddyProviderTest do
  use ExUnit.Case, async: true

  alias HostKit.Addr.Resource
  alias HostKit.Caddy.Directive.{Encode, ReverseProxy}
  alias HostKit.Caddy.Site

  test "caddy provider contributes DSL and renderer" do
    project = HostKit.load!(fixture_path("caddy_project.hostkit"))

    assert HostKit.Plugins.Caddy in project.providers

    assert [
             %HostKit.Service{
               resources: [
                 %Site{
                   name: :search,
                   host: "search.elixir.toys",
                   directives: [
                     %Encode{formats: [:zstd, :gzip]},
                     %ReverseProxy{upstreams: ["127.0.0.1:4200"]}
                   ]
                 } = site
               ]
             }
           ] = project.services

    assert Site.id(site) == Resource.new(:caddy_site, :search)

    assert {:ok, rendered} = HostKit.Render.render(project, Resource.new(:caddy_site, :search))

    route = rendered |> IO.iodata_to_binary() |> Jason.decode!()

    assert get_in(route, ["match", Access.at(0), "host"]) == ["search.elixir.toys"]

    assert [subroute] = route["handle"]
    handlers = get_in(subroute, ["routes", Access.at(0), "handle"])

    assert %{"handler" => "encode", "encodings" => %{"gzip" => %{}, "zstd" => %{}}} in handlers

    assert %{
             "handler" => "reverse_proxy",
             "upstreams" => [%{"dial" => "127.0.0.1:4200"}]
           } in handlers
  end

  test "caddy provider applies site files" do
    tmp =
      Path.join(System.tmp_dir!(), "host-kit-caddy-apply-#{System.unique_integer([:positive])}")

    Elixir.File.mkdir_p!(tmp)
    on_exit(fn -> Elixir.File.rm_rf(tmp) end)

    previous = System.get_env("HOST_KIT_CADDY_TEST_SITES_DIR")
    System.put_env("HOST_KIT_CADDY_TEST_SITES_DIR", tmp)
    on_exit(fn -> restore_env(previous) end)

    project = HostKit.load!(fixture_path("caddy_local_project.hostkit"))
    {:ok, plan} = HostKit.plan(project)

    assert {:ok, _results} = HostKit.apply(plan, confirm: true)
    assert File.read!(Path.join(tmp, "exograph-search.caddy")) =~ "reverse_proxy 127.0.0.1:4200"
  end

  test "caddy DSL is unavailable without provider import" do
    source = """
    defmodule HostKit.CaddyWithoutProviderFixture do
      use HostKit.DSL

      project :demo do
        service :web do
          caddy_site :search, "search.elixir.toys" do
            reverse_proxy "127.0.0.1:4200"
          end
        end
      end
    end
    """

    assert_raise CompileError, fn -> Code.compile_string(source) end
  end

  defp restore_env(nil), do: System.delete_env("HOST_KIT_CADDY_TEST_SITES_DIR")
  defp restore_env(value), do: System.put_env("HOST_KIT_CADDY_TEST_SITES_DIR", value)

  defp fixture_path(name), do: Path.expand("fixtures/#{name}", __DIR__)
end
