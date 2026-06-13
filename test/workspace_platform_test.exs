defmodule HostKit.WorkspacePlatformTest do
  use ExUnit.Case, async: true

  test "tenant scopes a workspace and records quota" do
    source = """
    use HostKit.DSL

    project :demo do
      tenant :alice, quota: [memory: "4G"] do
        service :agent do
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [%HostKit.Tenant{name: :alice, quota: [memory: "4G"]}] = project.tenants
    assert [service] = project.services
    assert service.meta.workspace == %{name: :alice, owner: :alice}
  end

  test "builds workspace exec specs" do
    source = """
    use HostKit.DSL

    project :demo do
      roots data: "/var/lib/hostkit/workspaces"
      prefixes user: "hk-", unit: "hk-ws-"

      workspace :blog, owner: :alice do
        agent port: 4173
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)

    assert {:ok, spec} =
             HostKit.Workspace.exec_spec(project, :alice, :blog, ["mix", "test"],
               name: "test-run"
             )

    assert spec.name == "test-run"
    assert spec.command == ["mix", "test"]
    assert spec.user == "hk-alice-blog-agent"
    assert spec.working_directory == "/var/lib/hostkit/workspaces/alice/blog/agent"
  end

  test "inside monitor execution is pending workspace agent" do
    source = """
    use HostKit.DSL

    project :demo do
      workspace :blog, owner: :alice do
        service :preview do
          inside do
            monitor :mix, task: "test"
          end
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert {:ok, [result]} = HostKit.Workspace.run_inside_monitors(project)
    assert result.status == :error
    assert result.reason == :pending_workspace_agent
  end
end
