defmodule HostKit.Apply.EventsTest do
  use ExUnit.Case, async: true

  alias HostKit.{Change, Plan}

  test "apply events include lifecycle metadata for phased commands" do
    command =
      HostKit.Resources.Command.new(:migrate,
        exec: {"true", []},
        phase: :before_start,
        down: :noop
      )

    plan = %Plan{
      project: %HostKit.Project{name: :events},
      changes: [%Change{action: :create, resource_id: {:command, :migrate}, after: command}]
    }

    assert {:ok, _results} = HostKit.apply(plan, confirm: true, reporter: self())

    assert_receive {HostKit.Apply,
                    %HostKit.Apply.Event{
                      type: :change_started,
                      lifecycle: %{phase: :before_start, operation: :migrate, direction: :up}
                    }}
  end

  test "readiness emits service and health progress events" do
    readiness =
      HostKit.Resources.Readiness.new(:app_ready,
        checks: [
          %HostKit.Readiness.Systemd{unit: "demo.service", restart: true},
          %HostKit.Readiness.HTTP{url: "http://127.0.0.1:9/health"}
        ],
        timeout: 1,
        interval: 1
      )

    plan = %Plan{
      project: %HostKit.Project{name: :events},
      changes: [%Change{action: :create, resource_id: {:readiness, :app_ready}, after: readiness}]
    }

    assert {:error, _reason} = HostKit.apply(plan, confirm: true, reporter: self())

    assert_receive {HostKit.Apply, %HostKit.Apply.Event{type: :readiness_started}}
    assert_receive {HostKit.Apply, %HostKit.Apply.Event{type: :health_check_started}}
    assert_receive {HostKit.Apply, %HostKit.Apply.Event{type: :service_restart_started}}
    assert_receive {HostKit.Apply, %HostKit.Apply.Event{type: :readiness_failed}}
  end
end
