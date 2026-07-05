defmodule HostKit.Plan.ArtifactTest do
  use ExUnit.Case, async: true

  alias HostKit.Plan.Artifact

  test "saves and loads resolved plans" do
    package =
      HostKit.Resources.Package.new(:curl,
        as: "curl",
        meta: %{source: %{file: "infra.exs", line: 12}}
      )

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
    assert json["version"] == 1
    assert json["generated_at"]
    assert json["target"] == %{"kind" => "local", "package_repo" => "debian_13"}
    assert json["stats"]["actions"]["create"] == 1
    assert json["stats"]["resources"] == %{"package" => 1}
    assert json["stats"]["changes_by_type"]["package"]["create"] == 1
    assert [change] = json["changes"]
    assert change["source"] == %{"file" => "infra.exs", "line" => 12}
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

  test "saves and loads plans with project metadata structs" do
    firewall = %HostKit.Firewall{
      name: :demo,
      path: "/etc/nftables.d/demo.nft",
      rules: [%HostKit.Firewall.Rule{action: :allow, protocol: :udp, ports: 1024..65_535}]
    }

    storage = %{
      state: %HostKit.Storage.Volume{name: :state, path: "/var/lib/demo", backup: true}
    }

    plan = %HostKit.Plan{
      project: %HostKit.Project{name: :demo, meta: %{firewall: firewall, storage: storage}},
      resources: [firewall]
    }

    path =
      Path.join(
        System.tmp_dir!(),
        "host-kit-range-plan-#{System.unique_integer([:positive])}.json"
      )

    assert :ok = Artifact.save(path, plan)
    assert {:ok, loaded} = Artifact.load(path)
    assert loaded.project.meta.firewall.rules |> hd() |> Map.fetch!(:ports) == 1024..65_535
    assert loaded.project.meta.storage == storage
    assert loaded.resources == [firewall]
  end

  test "saves and loads plans with readiness checks" do
    readiness =
      HostKit.Resources.Readiness.new(:ready,
        checks: [
          %HostKit.Readiness.Systemd{unit: "demo.service", restart: true, kill: true},
          %HostKit.Readiness.HTTP{url: "http://127.0.0.1:4000/health"}
        ]
      )

    plan = %HostKit.Plan{
      project: %HostKit.Project{name: :demo},
      resources: [readiness],
      changes: [
        %HostKit.Change{
          action: :update,
          resource_id: HostKit.Resources.Readiness.id(readiness),
          after: readiness,
          reason: {:triggered_by, []}
        }
      ]
    }

    path =
      Path.join(
        System.tmp_dir!(),
        "host-kit-readiness-plan-#{System.unique_integer([:positive])}.json"
      )

    assert :ok = Artifact.save(path, plan)
    assert {:ok, loaded} = Artifact.load(path)
    assert loaded.resources == [readiness]
    assert [%HostKit.Change{after: ^readiness}] = loaded.changes
  end

  test "saves and loads plans with binary resource content" do
    content = <<0x89, ?P, ?N, ?G, 0, 255>>
    file = HostKit.Resources.File.new("/srv/demo/card.png", content: content)
    plan = %HostKit.Plan{project: %HostKit.Project{name: :demo}, resources: [file]}

    path =
      Path.join(
        System.tmp_dir!(),
        "host-kit-binary-plan-#{System.unique_integer([:positive])}.json"
      )

    assert :ok = Artifact.save(path, plan)
    assert {:ok, json} = path |> File.read!() |> Jason.decode()

    assert [
             %{
               "fields" => %{
                 "entries" => entries
               }
             }
           ] = json["resources"]

    assert [_key, %{"$type" => "binary", "encoding" => "base64"}] =
             Enum.find(entries, fn [key, _value] -> key["value"] == "content" end)

    assert {:ok, loaded} = Artifact.load(path)
    assert loaded.resources == [file]
  end

  test "includes down plan stats" do
    package = HostKit.Resources.Package.new(:git, as: "git")

    plan = %HostKit.Plan{
      project: %HostKit.Project{name: :demo},
      changes: [
        %HostKit.Change{
          action: :create,
          resource_id: {:package, :git},
          after: package,
          reason: :missing
        }
      ]
    }

    assert {:ok, down_plan} = HostKit.down(plan)
    artifact = Artifact.from_plan(down_plan)

    assert artifact.stats["down_plan"] == %{
             source_changes: 1,
             reversible_changes: 0,
             noop_changes: 0,
             skipped_changes: 1,
             reversible_percent: 0.0,
             skipped_by_reason: %{"delete_not_supported" => 1},
             skipped_by_type: %{"package" => 1}
           }
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

  test "structured config artifacts omit redacted actual values" do
    path =
      Path.join(
        System.tmp_dir!(),
        "host-kit-config-artifact-#{System.unique_integer([:positive])}.json"
      )

    config =
      HostKit.Resources.ConfigFile.new("/etc/app.ini", :ini,
        content: [server: [DOMAIN: "example.test", TOKEN: :redacted]]
      )

    plan = %HostKit.Plan{
      project: %HostKit.Project{name: :demo},
      resources: [config],
      changes: [
        %HostKit.Change{
          action: :no_op,
          resource_id: HostKit.Resources.ConfigFile.id(config),
          before: %{
            config
            | meta: %{actual_public_entries: %{{"server", "DOMAIN"} => "example.test"}}
          },
          after: config,
          reason: :in_sync,
          diff: HostKit.Diff.config_file(config, %{{"server", "DOMAIN"} => "old.example.test"})
        }
      ],
      summary: %{no_op: 1}
    }

    assert :ok = Artifact.save(path, plan)

    content = File.read!(path)
    assert content =~ "example.test"
    assert content =~ "old.example.test"
    assert content =~ "redacted"
    refute content =~ "actual-secret-value"

    assert {:ok, loaded} = Artifact.load(path)

    assert [
             %HostKit.Change{
               action: :no_op,
               diff: %HostKit.Diff{changes: [%HostKit.Diff.Entry{}]}
             }
           ] =
             loaded.changes
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
