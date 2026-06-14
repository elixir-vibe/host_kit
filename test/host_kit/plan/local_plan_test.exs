defmodule HostKit.LocalPlanTest do
  use ExUnit.Case, async: true

  alias HostKit.Resources.Directory
  alias HostKit.Resources.File, as: FileResource

  test "read-only local plan reports existing file as in sync" do
    tmp = Path.join(System.tmp_dir!(), "host-kit-#{System.unique_integer([:positive])}")
    path = Path.join(tmp, "config.txt")

    Elixir.File.mkdir_p!(tmp)
    Elixir.File.write!(path, "hello")
    Elixir.File.chmod!(path, 0o644)
    on_exit(fn -> Elixir.File.rm_rf(tmp) end)

    %{owner: owner, group: group} = stat_metadata!(path)

    project =
      project_with(%FileResource{
        path: path,
        content: "hello",
        owner: owner,
        group: group,
        mode: 0o644
      })

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%HostKit.Change{action: :no_op, reason: :in_sync}] = plan.changes
  end

  test "read-only local plan reports missing directory as create" do
    path = Path.join(System.tmp_dir!(), "host-kit-missing-#{System.unique_integer([:positive])}")
    project = project_with(%Directory{path: path})

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%HostKit.Change{action: :create, before: nil, reason: :missing}] = plan.changes
  end

  test "read-only local plan reports mode drift" do
    tmp = Path.join(System.tmp_dir!(), "host-kit-#{System.unique_integer([:positive])}")
    path = Path.join(tmp, "config.txt")

    Elixir.File.mkdir_p!(tmp)
    Elixir.File.write!(path, "hello")
    Elixir.File.chmod!(path, 0o600)
    on_exit(fn -> Elixir.File.rm_rf(tmp) end)

    project = project_with(%FileResource{path: path, content: "hello", mode: 0o644})

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%HostKit.Change{action: :update, reason: :drift}] = plan.changes
  end

  defp stat_metadata!(path) do
    case System.cmd("stat", ["-c", "%U:%G:%a", path], stderr_to_stdout: true) do
      {output, 0} ->
        parse_stat_output(output)

      {_output, _status} ->
        {output, 0} = System.cmd("stat", ["-f", "%Su:%Sg:%Lp", path], stderr_to_stdout: true)
        parse_stat_output(output)
    end
  end

  defp parse_stat_output(output) do
    [owner, group, mode] = output |> String.trim() |> String.split(":", parts: 3)
    %{owner: owner, group: group, mode: String.to_integer(mode, 8)}
  end

  defp project_with(resource) do
    %HostKit.Project{
      name: :local_test,
      services: [%HostKit.Service{name: :fixture, resources: [resource]}]
    }
  end
end
