defmodule HostKit.Examples.LivebookDemoInstanceTest do
  use ExUnit.Case, async: true

  test "livebook demo instance example stays loadable" do
    project = HostKit.load!("examples/livebook_demo_instance.exs")

    assert project.name == :livebook_demo
    assert [instance] = project.instances
    assert instance.name == :hostkit_livebook_demo
    assert instance.backend == :incus
    assert instance.lifecycle == :ephemeral
    assert [%HostKit.Host{name: :guest}] = instance.hosts

    assert {:ok, plan} = HostKit.plan(project)

    assert [%HostKit.Change{action: :create, resource_id: {:instance, :hostkit_livebook_demo}}] =
             plan.changes
  end
end
