defmodule HostKit.Resources.FileTest do
  use ExUnit.Case, async: true

  alias HostKit.Resources.File, as: FileResource

  test "redacted file content compares only metadata" do
    tmp = Path.join(System.tmp_dir!(), "host-kit-redacted-#{System.unique_integer([:positive])}")
    path = Path.join(tmp, "secret.conf")

    Elixir.File.mkdir_p!(tmp)
    Elixir.File.write!(path, "actual secret")
    Elixir.File.chmod!(path, 0o600)
    on_exit(fn -> Elixir.File.rm_rf(tmp) end)

    %{owner: owner, group: group} = stat_metadata!(path)

    project =
      project_with(%FileResource{
        path: path,
        content: :redacted,
        owner: owner,
        group: group,
        mode: 0o600
      })

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%HostKit.Change{action: :no_op, reason: :in_sync}] = plan.changes
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
    [owner, group, _mode] = output |> String.trim() |> String.split(":", parts: 3)
    %{owner: owner, group: group}
  end

  defp project_with(resource) do
    %HostKit.Project{
      name: :redacted_test,
      services: [%HostKit.Service{name: :fixture, resources: [resource]}]
    }
  end
end
