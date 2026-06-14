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

  test "resource inspect output is compact for Livebook display" do
    assert inspect(%HostKit.Resources.Package{name: :caddy, system_name: "caddy"}) ==
             "#HostKit.Package<caddy -> caddy>"

    assert inspect(%HostKit.Resources.Directory{path: "/srv/app"}) ==
             "#HostKit.Directory</srv/app>"

    assert inspect(%HostKit.Resources.File{path: "/etc/app.env"}) ==
             "#HostKit.File</etc/app.env>"

    assert inspect(%HostKit.Systemd.Service{name: "app.service"}) ==
             "#HostKit.Systemd.Service<app.service>"

    assert inspect(%HostKit.Caddy.Site{name: :app, host: ":4000"}) ==
             "#HostKit.Caddy.Site<app :4000>"
  end

  test "plan and change inspect output is compact" do
    change = %HostKit.Change{
      action: :read,
      resource_id: {:directory, "/srv/app"},
      reason: {:read_error, {:remote_read_failed, ":econnrefused"}}
    }

    plan = %HostKit.Plan{changes: [change]}

    assert inspect(change) ==
             "#HostKit.Change<read directory./srv/app read failed: remote read failed: SSH connection refused>"

    assert inspect(plan) ==
             "#HostKit.Plan< create=0 update=0 delete=0 read_errors=1 unchanged=0>"
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

  test "transport read errors use human language" do
    assert HostKit.Error.format({:read_error, {:remote_read_failed, ":econnrefused"}}) ==
             "read failed: remote read failed: SSH connection refused"
  end
end
