defmodule HostKit.Plan.ArtifactTest do
  use ExUnit.Case, async: true

  alias HostKit.Plan.Artifact

  test "saves and loads resolved plans" do
    package = HostKit.Resources.Package.new(:curl, as: "curl")

    plan = %HostKit.Plan{
      project: %HostKit.Project{name: :demo},
      resources: [package],
      changes: [
        %HostKit.Change{
          action: :create,
          resource_id: HostKit.Resources.Package.id(package),
          after: package,
          reason: :missing
        }
      ],
      summary: %{create: 1},
      opts: [reader: HostKit.Local]
    }

    path =
      Path.join(System.tmp_dir!(), "host-kit-plan-#{System.unique_integer([:positive])}.json")

    assert :ok =
             Artifact.save(path, plan,
               target_metadata: %{"kind" => "local", "package_repo" => "debian_13"}
             )

    assert {:ok, json} = path |> File.read!() |> Jason.decode()
    assert json["target"] == %{"kind" => "local", "package_repo" => "debian_13"}
    refute Map.has_key?(json, "plan")

    assert [%{"$type" => "struct", "module" => "Elixir.HostKit.Resources.Package"}] =
             json["resources"]

    assert {:ok, loaded} = Artifact.load(path)
    assert loaded.project == plan.project
    assert loaded.resources == plan.resources
    assert loaded.changes == plan.changes
    assert loaded.summary == plan.summary
    assert loaded.opts == []
  end

  test "loads user atoms as strings instead of creating atoms" do
    assert HostKit.Resource.load(%{
             "$type" => "atom",
             "value" => "hostkit_user_atom_not_existing"
           }) ==
             "hostkit_user_atom_not_existing"
  end

  test "rejects unsupported artifact modules" do
    artifact = %Artifact{
      project: %{
        "$type" => "struct",
        "module" => "Elixir.HostKit.Agent.State",
        "fields" => %{"last_plan" => nil}
      },
      resources: [],
      changes: [],
      summary: %{}
    }

    assert {:error, %ArgumentError{message: message}} = Artifact.to_plan(artifact)
    assert message =~ "unsupported HostKit artifact module"
  end

  test "rejects unsupported artifact versions" do
    assert {:error,
            %JSONCodec.Error{path: [:version], reason: :unsupported_plan_artifact_version}} =
             Artifact.from_map(%{"version" => 2, "target" => nil, "plan" => ""})
  end
end
