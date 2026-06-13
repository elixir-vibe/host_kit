defmodule HostKit.WorkspaceAgentTest do
  use ExUnit.Case, async: true

  test "workspace_agent expands to ordinary HostKit resources" do
    source = """
    use HostKit.DSL

    project :demo do
      roots data: "/var/lib/hostkit/workspaces"
      prefixes user: "hk-", unit: "hk-ws-"

      workspace :blog, owner: :alice do
        workspace_agent port: 4173
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services
    assert service.name == :agent
    assert service.meta.workspace == %{name: :blog, owner: :alice}
    assert service.meta.path_name == "alice/blog/agent"

    assert [user, directory, unit] = service.resources
    assert %HostKit.Resources.User{name: "hk-alice-blog-agent", system: true} = user

    assert %HostKit.Resources.Directory{
             path: "/var/lib/hostkit/workspaces/alice/blog/agent",
             mode: 0o750
           } = directory

    assert %HostKit.Systemd.Service{name: "hk-ws-alice-blog-agent.service"} = unit
    assert unit.service[:user] == "hk-alice-blog-agent"
    assert unit.service[:working_directory] == "/var/lib/hostkit/workspaces/alice/blog/agent"
    assert unit.meta.listen == [%{port: 4173, on: {127, 0, 0, 1}}]
    assert unit.service[:ip_address_deny] == "any"
    assert unit.service[:ip_address_allow] == ["localhost"]
    assert [%HostKit.Monitor.Check{type: :systemd}] = unit.meta.monitor
  end
end
