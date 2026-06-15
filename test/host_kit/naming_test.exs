defmodule HostKit.NamingTest do
  use ExUnit.Case, async: true

  alias HostKit.Naming

  test "path and identity segments have distinct normalization rules" do
    assert Naming.path_segment(:hex_mirror) == "hex_mirror"
    assert Naming.identity_segment(:hex_mirror) == "hex-mirror"
    assert Naming.identity_path("alice/blog_preview") == "alice-blog-preview"
  end

  test "resource names are underscore-safe" do
    assert Naming.resource([:gatehouse, "my-app", :ready]) == "gatehouse_my_app_ready"
    assert Naming.readiness(:gatehouse, "my-app") == "gatehouse_my_app_ready"
  end

  test "ingress route names use shared route suffix normalization" do
    assert Naming.ingress_route(:edge, "www.elixir.toys", 1) == "edge_www_elixir_toys_1"
  end

  test "workspace identities and unit helpers are shared" do
    assert Naming.workspace_path(:alice, "blog", :agent) == "alice/blog/agent"
    assert Naming.workspace_identity(:alice, "blog/preview", :agent) == "alice-blog-preview-agent"
    assert Naming.prefixed("hk-", :blog_agent) == "hk-blog-agent"
    assert Naming.systemd_unit("hk-blog-agent") == "hk-blog-agent.service"
    assert Naming.systemd_unit("hk-blog-agent.service") == "hk-blog-agent.service"
    assert Naming.systemd_unit("hk-blog-agent.timer") == "hk-blog-agent.timer"
    assert Naming.systemd_unit("hk-blog-agent", "-sync.timer") == "hk-blog-agent-sync.timer"
  end

  test "Elixir release and capability names are underscore-safe" do
    assert Naming.elixir_release("hello-phoenix") == "hello_phoenix"
    assert Naming.elixir_release(:hello_phoenix) == "hello_phoenix"
    assert Naming.capability("ca-certificates") == :ca_certificates
    assert Naming.capability("custom-capability") == "custom-capability"
  end
end
