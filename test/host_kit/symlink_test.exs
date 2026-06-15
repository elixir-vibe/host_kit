defmodule HostKit.SymlinkTest do
  use HostKit.Case, async: true

  alias HostKit.Change
  alias HostKit.Resources.Symlink

  test "DSL declares symlink resources" do
    project =
      Code.eval_quoted(
        quote do
          use HostKit.DSL

          project :links do
            symlink("/opt/app/current", to: "/opt/app/releases/v1")
          end
        end
      )
      |> elem(0)

    assert [%Symlink{path: "/opt/app/current", to: "/opt/app/releases/v1"}] =
             HostKit.Project.resources(project)
  end

  test "local plan treats matching symlink as in sync" do
    tmp = tmp_dir!()
    target = Path.join(tmp, "target")
    link = Path.join(tmp, "current")
    File.mkdir_p!(target)
    File.ln_s!(target, link)

    project = project_with_symlink(link, target)

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%Change{action: :no_op, reason: :in_sync}] = plan.changes
  end

  test "local plan detects symlink target drift" do
    tmp = tmp_dir!()
    old_target = Path.join(tmp, "old")
    new_target = Path.join(tmp, "new")
    link = Path.join(tmp, "current")
    File.mkdir_p!(old_target)
    File.mkdir_p!(new_target)
    File.ln_s!(old_target, link)

    project = project_with_symlink(link, new_target)

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)

    assert [%Change{action: :update, reason: :drift, before: %Symlink{to: ^old_target}}] =
             plan.changes
  end

  test "apply creates symlink" do
    tmp = tmp_dir!()
    target = Path.join(tmp, "target")
    link = Path.join(tmp, "nested/current")
    File.mkdir_p!(target)

    project = project_with_symlink(link, target)
    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%Change{action: :create}] = plan.changes

    assert {:ok, [%{status: :applied}]} = HostKit.Apply.run(plan, confirm: true)
    assert {:ok, ^target} = File.read_link(link)
  end

  defp tmp_dir! do
    tmp = Path.join(System.tmp_dir!(), "host-kit-symlink-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    tmp
  end

  defp project_with_symlink(link, target) do
    Code.eval_quoted(
      quote do
        use HostKit.DSL

        project :links do
          symlink(unquote(link), to: unquote(target))
        end
      end
    )
    |> elem(0)
  end
end
