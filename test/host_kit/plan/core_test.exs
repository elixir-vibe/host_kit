defmodule HostKit.PlanTest do
  use HostKit.Case, async: true

  alias HostKit.Addr.Resource
  alias HostKit.Caddy.Site
  alias HostKit.Change

  test "plan contains create changes for desired resources" do
    project = HostKit.load!(fixture_path("caddy_project.hostkit"))

    assert {:ok, plan} = HostKit.plan(project)

    assert [
             %Change{
               action: :create,
               resource_id: %Resource{type: :caddy_site, name: "search.elixir.toys"},
               before: nil,
               after: %Site{host: "search.elixir.toys"},
               reason: :desired_state
             }
           ] = plan.changes

    assert plan.summary == %{caddy_site: 1}
  end
end
