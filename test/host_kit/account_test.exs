defmodule HostKit.AccountTest do
  use ExUnit.Case, async: true

  test "account declarations and references are consumed by resources" do
    project =
      Code.eval_string("""
      use HostKit.DSL

      project :accounts do
        account :app, system: true, home: "/var/lib/app"

        service :app do
          directory "/var/lib/app", owner: account(:app), group: account(:app)

          daemon "app.service" do
            service_user account(:app)
            service_group account(:app)
            exec_start ["/bin/true"]
          end
        end
      end
      """)
      |> elem(0)

    assert [%HostKit.Resources.Account{name: "app", system: true}] = project.resources

    assert [_account, %HostKit.Resources.Directory{owner: "app", group: "app"}, service] =
             HostKit.Project.resources(project)

    assert %HostKit.Systemd.Service{service: service_opts} = service
    assert Keyword.get(service_opts, :user) == "app"
    assert Keyword.get(service_opts, :group) == "app"
  end
end
