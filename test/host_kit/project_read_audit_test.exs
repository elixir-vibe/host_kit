defmodule HostKit.ProjectReadAuditTest do
  use HostKit.Case, async: false

  alias HostKit.Change
  alias HostKit.Resources.File, as: FileResource

  test "Project.audit returns a plan and Project.read returns current snapshots" do
    path = Path.join(tmp_dir("project-read-audit"), "demo.txt")
    File.write!(path, "current")

    project =
      %HostKit.Project{name: :audit}
      |> HostKit.Project.add_resource(%FileResource{path: path, content: "desired"})

    assert {:ok, plan} = HostKit.Project.audit(project, reader: HostKit.Local)
    assert [%Change{action: :update, before: %FileResource{content: "current"}}] = plan.changes

    assert {:ok, [%FileResource{content: "current"}]} =
             HostKit.Project.read(project, reader: HostKit.Local)
  after
    cleanup_tmp("project-read-audit")
  end

  defp tmp_dir(name) do
    path = Path.join(System.tmp_dir!(), "hostkit-#{name}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp cleanup_tmp(name) do
    HostKit.SafeTmp.rm_rf!(Path.join(System.tmp_dir!(), "hostkit-#{name}"), "hostkit-")
  end
end
