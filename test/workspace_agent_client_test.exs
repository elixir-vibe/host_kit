defmodule HostKit.WorkspaceAgentClientTest do
  use ExUnit.Case, async: true

  defmodule Client do
    @behaviour HostKit.Workspace.Agent.Client

    @impl true
    def status(socket, _opts), do: {:ok, %{socket: socket, status: :ok}}

    @impl true
    def exec(socket, argv, _opts), do: {:ok, %{socket: socket, argv: argv, status: :started}}

    @impl true
    def run_checks(socket, checks, _opts) do
      {:ok, Enum.map(checks, &HostKit.Monitor.Result.ok(&1, %{socket: socket}))}
    end
  end

  test "workspace exec can go through agent client" do
    project = project()

    assert {:ok, result} =
             HostKit.Workspace.exec(project, :alice, :blog, ["mix", "test"],
               via: :agent,
               client: Client
             )

    assert result.socket == "/run/hostkit/workspaces/alice-blog-agent.sock"
    assert result.argv == ["mix", "test"]
  end

  test "inside monitors run through agent client" do
    project = project()

    assert {:ok, [result]} = HostKit.Workspace.run_inside_monitors(project, client: Client)
    assert result.status == :ok
    assert result.observed.socket == "/run/hostkit/workspaces/alice-blog-agent.sock"
  end

  defp project do
    source = """
    use HostKit.DSL

    project :demo do
      roots data: "/var/lib/hostkit/workspaces"

      workspace :blog, owner: :alice do
        agent port: 4173

        service :preview do
          inside do
            monitor :mix, task: "test"
          end
        end
      end
    end
    """

    {project, _binding} = Code.eval_string(source)
    project
  end
end
