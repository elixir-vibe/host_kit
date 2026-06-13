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
