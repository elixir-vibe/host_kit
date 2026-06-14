defmodule HostKit.InspectAndErrorFormatTest do
  use ExUnit.Case, async: true

  test "compact Inspect implementations for reference structs" do
    assert inspect(HostKit.Endpoint.new(:app, :http)) == "#HostKit.Endpoint<app.http>"

    assert inspect(
             HostKit.Endpoint.new(:app, :http, protocol: :http, host: "127.0.0.1", port: 4000)
           ) ==
             "#HostKit.Endpoint<app.http http://127.0.0.1:4000>"

    assert inspect(HostKit.Source.Ref.new(:app)) == "#HostKit.Source.Ref<app>"

    assert inspect(HostKit.Addr.Resource.new(:caddy_site, :app)) ==
             "#HostKit.Resource<caddy_site.app>"

    assert inspect(
             HostKit.Addr.AbsResource.new(
               [:root, :web],
               HostKit.Addr.Resource.new(:file, "/tmp/app")
             )
           ) == "#HostKit.AbsResource<module.web.file./tmp/app>"
  end

  test "source identity inspect is compact" do
    identity = %HostKit.Source.Identity{
      type: :git,
      uri: "https://example.com/app.git",
      ref: "main",
      ref_kind: :branch,
      revision: "1234567890abcdef",
      tree: "tree",
      checkout: "/opt/app",
      path: "apps/web"
    }

    assert inspect(identity) ==
             "#HostKit.Source.Identity<git https://example.com/app.git@1234567890ab path=apps/web>"
  end

  test "command errors summarize shell scripts" do
    script = "set +e\necho hello\necho world"
    reason = {:command_failed, "sudo", ["sh", "-c", script], 1, "a long failure"}

    formatted = HostKit.Error.format(reason)

    assert formatted =~ "command failed (1): sudo sh -c <script sha256="
    assert formatted =~ "lines=3"
    assert formatted =~ "a long failure"
    refute formatted =~ "echo world"
  end
end
