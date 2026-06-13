defmodule HostKit.WorkspaceNextTest do
  use ExUnit.Case, async: true

  test "egress policy is metadata and renders nftables" do
    source = """
    use HostKit.DSL

    project :demo do
      prefixes user: "hk-"
      workspace :blog, owner: :alice do
        service :preview do
          egress allow: [:dns, :https], deny: :private
        end
      end
    end
    """

    {project, _} = Code.eval_string(source)
    assert [service] = project.services
    assert service.meta.egress.user == "hk-alice-blog-preview"
    rendered = HostKit.Firewall.Nftables.render_egress(service.meta.egress)
    assert rendered =~ "udp dport 53 accept"
    assert rendered =~ "tcp dport 443 accept"
    assert rendered =~ "ip daddr 10.0.0.0/8 drop"
    assert rendered =~ "ip daddr 172.16.0.0/12 drop"
    assert rendered =~ "ip daddr 192.168.0.0/16 drop"
  end

  test "egress deny all drops other workspace traffic after allow rules" do
    egress = %HostKit.Workspace.Egress{user: "hk-alice-blog-preview", allow: [:dns], deny: :all}

    rendered = HostKit.Firewall.Nftables.render_egress(egress)
    assert rendered =~ "meta skuid hk-alice-blog-preview udp dport 53 accept"
    assert rendered =~ "meta skuid hk-alice-blog-preview drop"
  end

  test "unix client uses Erlang term transport and reports transport errors" do
    assert {:error, _reason} =
             HostKit.Workspace.Agent.UnixClient.status("/tmp/missing.sock", timeout: 10)
  end

  test "caddy access log config is richer" do
    site = %HostKit.Caddy.Site{
      name: :web,
      host: "web.example.com",
      meta: %{logs: %{driver: :caddy_access}}
    }

    map = [site] |> HostKit.Caddy.JSON.config_for_sites() |> HostKit.Caddy.JSON.to_map()
    logs = get_in(map, ["apps", "http", "servers", "srv0", "logs"])
    assert logs["default_logger_name"] == "hostkit_caddy_access"
    assert logs["logger_names"] != nil
  end
end
