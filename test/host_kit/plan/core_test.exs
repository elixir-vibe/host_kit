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

  test "plan triggers healthy readiness when an upstream dependency changes" do
    service = %HostKit.Systemd.Service{name: "demo.service"}

    readiness = %HostKit.Resources.Readiness{
      name: :demo_ready,
      checks: [%HostKit.Readiness.Systemd{unit: "demo.service", restart: true}]
    }

    project = %HostKit.Project{
      name: :demo,
      services: [
        %HostKit.Service{
          name: :demo,
          path: "demo",
          identity: "demo",
          resources: [service, readiness]
        }
      ]
    }

    assert {:ok, plan} = HostKit.plan(project, reader: __MODULE__.TriggeredReadinessReader)

    assert [
             %Change{resource_id: {:systemd_service, "demo.service"}, action: :create},
             %Change{
               resource_id: {:readiness, :demo_ready},
               action: :update,
               reason: {:triggered_by, [{:systemd_service, "demo.service"}]}
             }
           ] = plan.changes
  end

  test "plan leaves healthy readiness unchanged when dependencies do not change" do
    service = %HostKit.Systemd.Service{name: "demo.service"}

    readiness = %HostKit.Resources.Readiness{
      name: :demo_ready,
      checks: [%HostKit.Readiness.Systemd{unit: "demo.service", restart: true}]
    }

    project = %HostKit.Project{
      name: :demo,
      services: [
        %HostKit.Service{
          name: :demo,
          path: "demo",
          identity: "demo",
          resources: [service, readiness]
        }
      ]
    }

    assert {:ok, plan} = HostKit.plan(project, reader: __MODULE__.NoOpReadinessReader)

    assert [
             %Change{resource_id: {:systemd_service, "demo.service"}, action: :no_op},
             %Change{resource_id: {:readiness, :demo_ready}, action: :no_op}
           ] = plan.changes
  end

  test "plan can be scoped to declared services" do
    project = %HostKit.Project{
      name: :demo,
      services: [
        %HostKit.Service{
          name: :api,
          path: "api",
          identity: "api",
          resources: [%HostKit.Resources.Directory{path: "/srv/api"}]
        },
        %HostKit.Service{
          name: :worker,
          path: "background-worker",
          identity: "background_worker",
          resources: [%HostKit.Resources.Directory{path: "/srv/worker"}]
        }
      ]
    }

    assert {:ok, plan} = HostKit.plan(project, services: [:api])
    assert Enum.map(plan.changes, & &1.resource_id) == [{:directory, "/srv/api"}]

    assert {:ok, plan} = HostKit.plan(project, services: ["background-worker"])
    assert Enum.map(plan.changes, & &1.resource_id) == [{:directory, "/srv/worker"}]

    assert {:error, {:unknown_service, :missing}} = HostKit.plan(project, services: [:missing])
  end

  defmodule TriggeredReadinessReader do
    def read(%HostKit.Systemd.Service{}), do: {:ok, nil}
    def read(%HostKit.Resources.Readiness{} = readiness), do: {:ok, readiness}
  end

  defmodule NoOpReadinessReader do
    def read(%HostKit.Systemd.Service{} = service) do
      {:ok, %{service | meta: %{content: HostKit.Systemd.Service.render(service)}}}
    end

    def read(%HostKit.Resources.Readiness{} = readiness), do: {:ok, readiness}
  end
end
