defmodule HostKit.Net.AddrTest do
  use ExUnit.Case, async: true

  test "normalizes idiomatic IP forms" do
    assert HostKit.Net.Addr.normalize!(:loopback) == {127, 0, 0, 1}
    assert HostKit.Net.Addr.normalize!(:any) == {0, 0, 0, 0}
    assert HostKit.Net.Addr.normalize!({10, 44, 0, 0, 24}) == {10, 44, 0, 0, 24}
    assert HostKit.Net.Addr.normalize!({{10, 44, 0, 0}, 24}) == {10, 44, 0, 0, 24}
  end

  test "renders addresses" do
    assert HostKit.Net.Addr.to_string(:loopback) == "127.0.0.1"
    assert HostKit.Net.Addr.to_string({10, 44, 0, 0, 24}) == "10.44.0.0/24"
    assert HostKit.Net.Addr.systemd_allow(:loopback) == "localhost"
    assert HostKit.Net.Addr.systemd_deny(:all) == "any"
  end

  test "network policy compiles to systemd service directives" do
    source = """
    use HostKit.DSL

    project :demo do
      service :web do
        daemon "web.service" do
          run exec_start: ["/usr/bin/env", "true"]
          network_policy deny: :all, allow: [:loopback, {10, 44, 0, 0, 24}]
          listen 3000, on: :loopback
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [%HostKit.Systemd.Service{} = service] = HostKit.Project.resources(project)
    assert service.service[:ip_address_deny] == "any"
    assert service.service[:ip_address_allow] == ["localhost", "10.44.0.0/24"]
    assert service.service[:restrict_address_families] == "AF_INET AF_INET6 AF_UNIX"
    assert service.meta.network_policy == %{allow: [:loopback, {10, 44, 0, 0, 24}], deny: :all}
    assert service.meta.listen == [%{port: 3000, on: {127, 0, 0, 1}}]
  end
end
