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

  test "includes source identities" do
    source = %HostKit.Resources.Source{
      name: :app,
      uri: "https://github.com/elixir-vibe/host_kit.git",
      ref: "main",
      ref_kind: :branch,
      revision: "abc123",
      checkout: "/opt/app/source",
      path: "examples/hello",
      meta: %{tree: "def456"}
    }

    plan = %HostKit.Plan{project: %HostKit.Project{name: :demo}, resources: [source]}
    artifact = Artifact.from_plan(plan)

    assert artifact.sources == %{
             "app" => %{
               "type" => "git",
               "uri" => "https://github.com/elixir-vibe/host_kit.git",
               "ref" => "main",
               "ref_kind" => "branch",
               "revision" => "abc123",
               "tree" => "def456",
               "checkout" => "/opt/app/source",
               "path" => "examples/hello"
             }
           }
  end

  test "serializes secret references without resolved secret values" do
    env_var = "HOSTKIT_PLAN_ARTIFACT_SECRET_#{System.unique_integer([:positive])}"
    System.put_env(env_var, "super-secret-value")

    on_exit(fn -> System.delete_env(env_var) end)

    plan = %HostKit.Plan{
      project: %HostKit.Project{
        name: :demo,
        hosts: [
          %HostKit.Host{
            name: :prod,
            hostname: "example.test",
            user: "root",
            meta: %{ssh: [password: HostKit.Secret.env(env_var)]}
          }
        ]
      },
      resources: [],
      changes: [],
      summary: %{}
    }

    path =
      Path.join(
        System.tmp_dir!(),
        "host-kit-secret-plan-#{System.unique_integer([:positive])}.json"
      )

    assert :ok = Artifact.save(path, plan)

    content = File.read!(path)
    assert content =~ env_var
    refute content =~ "super-secret-value"

    assert {:ok, loaded} = Artifact.load(path)
    assert [%HostKit.Host{} = host] = loaded.project.hosts
    assert host.meta.ssh[:password] == HostKit.Secret.env(env_var)
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
