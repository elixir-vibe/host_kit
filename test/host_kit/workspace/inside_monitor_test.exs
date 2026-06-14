defmodule HostKit.WorkspaceInsideMonitorTest do
  use ExUnit.Case, async: true

  test "inside monitor declarations attach to workspace services" do
    source = """
    use HostKit.DSL

    project :demo do
      workspace :blog, owner: :alice do
        service :preview do
          inside do
            monitor :mix, task: "test", every: "5m"
            inside_monitor :port, port: 4000
            monitor :git, clean: true
          end
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services

    assert [
             %HostKit.Monitor.Check{type: :mix},
             %HostKit.Monitor.Check{type: :port},
             %HostKit.Monitor.Check{type: :git}
           ] = service.meta.inside_monitor

    assert [mix, port, git] = HostKit.Workspace.inside_monitors(project)
    assert mix.workspace == %{name: :blog, owner: :alice}
    assert mix.service == :preview
    assert mix.check.type == :mix
    assert mix.check.meta == %{}
    assert port.check.type == :port
    assert git.check.type == :git
  end
end
