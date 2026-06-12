defmodule HostKit.LocalPlanTest do
  use ExUnit.Case, async: true

  alias HostKit.Resources.Directory
  alias HostKit.Resources.File, as: FileResource

  test "read-only local plan reports existing file as in sync" do
    tmp = Path.join(System.tmp_dir!(), "host-kit-#{System.unique_integer([:positive])}")
    path = Path.join(tmp, "config.txt")

    Elixir.File.mkdir_p!(tmp)
    Elixir.File.write!(path, "hello")
    on_exit(fn -> Elixir.File.rm_rf(tmp) end)

    project = project_with(%FileResource{path: path, content: "hello"})

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%HostKit.Change{action: :no_op, reason: :in_sync}] = plan.changes
  end

  test "read-only local plan reports missing directory as create" do
    path = Path.join(System.tmp_dir!(), "host-kit-missing-#{System.unique_integer([:positive])}")
    project = project_with(%Directory{path: path})

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%HostKit.Change{action: :create, before: nil, reason: :missing}] = plan.changes
  end

  defp project_with(resource) do
    %HostKit.Project{
      name: :local_test,
      services: [%HostKit.Service{name: :fixture, resources: [resource]}]
    }
  end
end
