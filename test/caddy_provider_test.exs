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

    assert IO.iodata_to_binary(rendered) == """
           search.elixir.toys {
           \tencode zstd gzip
           \treverse_proxy 127.0.0.1:4200
           }
           """
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

  defp fixture_path(name), do: Path.expand("fixtures/#{name}", __DIR__)
end
