defmodule HostKit.IgnorePlanTest do
  use ExUnit.Case, async: true

  alias HostKit.Resources.Directory

  test "marks ignored resources as no-op" do
    project = %HostKit.Project{
      name: :demo,
      services: [%HostKit.Service{name: :app, resources: [%Directory{path: "/srv/demo"}]}]
    }

    assert {:ok, plan} = HostKit.plan(project, ignore: [{:directory, "/srv/demo"}])

    assert [change] = plan.changes
    assert change.action == :no_op
    assert change.reason == :ignored
    assert change.resource_id == {:directory, "/srv/demo"}
  end
end
