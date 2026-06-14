defmodule HostKit.WorkspaceEgressApplyTest do
  use ExUnit.Case, async: true

  defmodule Runner do
    @behaviour HostKit.Runner
    def cmd(_command, _args, _opts), do: {"", 0}
    def mkdir_p(_path, _opts), do: :ok

    def write_file(path, content, opts) do
      send(opts[:test_pid], {:write_file, path, IO.iodata_to_binary(content)})
      :ok
    end
  end

  test "workspace egress policies are project resources and applyable" do
    source = """
    use HostKit.DSL
    project :demo do
      prefixes user: "hk-"
      workspace :blog, owner: :alice do
        service :preview do
          egress allow: [:dns]
        end
      end
    end
    """

    {project, _} = Code.eval_string(source)

    assert [_egress] =
             Enum.filter(
               HostKit.Project.resources(project),
               &match?(%HostKit.Workspace.Egress{}, &1)
             )

    {:ok, plan} = HostKit.plan(project)
    assert {:ok, _} = HostKit.apply(plan, confirm: true, runner: {Runner, test_pid: self()})

    assert_received {:write_file, "/etc/nftables.d/hostkit-egress-hk-alice-blog-preview.nft",
                     content}

    assert content =~ "udp dport 53"
  end
end
