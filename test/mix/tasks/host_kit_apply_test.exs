defmodule Mix.Tasks.HostKit.ApplyTest do
  use ExUnit.Case, async: false

  alias HostKit.Plan.Artifact
  alias Mix.Tasks.HostKit.Apply

  setup do
    Mix.Task.reenable("host_kit.apply")
    :ok
  end

  test "rejects plan artifacts for a different package target" do
    path =
      Path.join(
        System.tmp_dir!(),
        "host-kit-apply-plan-#{System.unique_integer([:positive])}.json"
      )

    plan = %HostKit.Plan{project: %HostKit.Project{name: :demo}, changes: []}

    assert :ok =
             Artifact.save(path, plan,
               target_metadata: %{"package_repo" => "hostkit_target_that_should_not_exist"}
             )

    assert_raise Mix.Error, ~r/could not load HostKit plan artifact/, fn ->
      Apply.run(["--plan", path, "--dry-run"])
    end
  end
end
