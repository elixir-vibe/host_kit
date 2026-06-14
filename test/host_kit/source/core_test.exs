defmodule HostKit.SourceTest do
  use ExUnit.Case, async: false

  alias HostKit.Resources.Source

  test "source DSL records git source metadata" do
    defmodule SourceDslProject do
      use HostKit

      def project do
        project :source_dsl do
          service :app do
            source(:app,
              github: "elixir-vibe/host_kit",
              ref: "main",
              checkout: "/opt/app/source",
              path: "examples/hello_phoenix"
            )
          end
        end
      end
    end

    [source] = HostKit.Project.resources(SourceDslProject.project())

    assert %Source{} = source
    assert source.name == :app
    assert source.type == :git
    assert source.uri == "https://github.com/elixir-vibe/host_kit.git"
    assert source.ref == "main"
    assert source.checkout == "/opt/app/source"
    assert Source.app_path(source) == "/opt/app/source/examples/hello_phoenix"
  end

  test "source identity is an internal struct" do
    source = %Source{
      name: :app,
      uri: "https://github.com/elixir-vibe/host_kit.git",
      ref: "main",
      ref_kind: :branch,
      revision: "abc123",
      checkout: "/opt/app/source",
      meta: %{tree: "def456"}
    }

    assert %HostKit.Source.Identity{
             type: :git,
             uri: "https://github.com/elixir-vibe/host_kit.git",
             ref_kind: :branch,
             revision: "abc123",
             tree: "def456"
           } = Source.identity(source)
  end

  test "git source requires a git command provider" do
    source = Source.new(:app, git: fixture_repo_uri(), ref: "main", checkout: "/tmp/app")

    assert [%{name: "git"}] = HostKit.CommandAnalysis.required_command_refs(source)

    project = %HostKit.Project{
      name: :source_missing_git,
      services: [%HostKit.Service{name: :app, resources: [source]}]
    }

    assert {:error, %HostKit.Diagnostics{errors: [diagnostic]}} = HostKit.plan(project)
    assert diagnostic.code == :missing_command_provider
    assert diagnostic.details.command == "git"
  end

  test "git source branch refs produce plan warnings" do
    repo = create_repo!()

    project = %HostKit.Project{
      name: :source_warning,
      services: [
        %HostKit.Service{
          name: :app,
          resources: [
            HostKit.Resources.Package.new(:git, as: "git"),
            Source.new(:app,
              git: repo.uri,
              ref: "main",
              checkout: Path.join(repo.root, "checkout")
            )
          ]
        }
      ]
    }

    assert {:ok, plan} = HostKit.plan(project)

    assert [%HostKit.Diagnostic{code: :source_mutable_ref, severity: :warning}] =
             plan.diagnostics.warnings
  end

  test "dirty git source checkout is a plan error by default" do
    repo = create_repo!()
    checkout = Path.join(repo.root, "checkout")
    source = Source.new(:app, git: repo.uri, ref: "main", checkout: checkout)

    assert {:ok, resolved} = HostKit.Source.Git.resolve(source)
    assert :ok = HostKit.Source.Git.apply(resolved, [])
    File.write!(Path.join(checkout, "README.md"), "dirty\n")

    project = %HostKit.Project{
      name: :source_dirty,
      services: [
        %HostKit.Service{
          name: :app,
          resources: [HostKit.Resources.Package.new(:git, as: "git"), source]
        }
      ]
    }

    assert {:error, %HostKit.Diagnostics{errors: [diagnostic]}} =
             HostKit.plan(project, reader: HostKit.Local)

    assert diagnostic.code == :source_checkout_dirty
    assert diagnostic.details.checkout == checkout
  end

  test "git source resolves branch refs from ls-remote semantics" do
    repo = create_repo!()

    source =
      Source.new(:app, git: repo.uri, ref: "main", checkout: Path.join(repo.root, "checkout"))

    assert {:ok, resolved} = HostKit.Source.Git.resolve(source)
    assert resolved.ref_kind == :branch
    assert resolved.revision == repo.revision
  end

  test "git source apply pins resolved revision and plans no-op when current" do
    repo = create_repo!()
    checkout = Path.join(repo.root, "checkout")

    project = %HostKit.Project{
      name: :source_apply,
      services: [
        %HostKit.Service{
          name: :app,
          resources: [
            HostKit.Resources.Package.new(:git, as: "git"),
            Source.new(:app, git: repo.uri, ref: "main", checkout: checkout)
          ]
        }
      ]
    }

    opts = [reader: HostKit.Local]
    assert {:ok, plan} = HostKit.plan(project, opts)

    assert Enum.any?(
             plan.changes,
             &match?(%HostKit.Change{resource_id: {:source, :app}, action: :create}, &1)
           )

    source_change = Enum.find(plan.changes, &(&1.resource_id == {:source, :app}))
    assert source_change.after.revision == repo.revision

    assert {:ok, _results} = HostKit.apply(plan, confirm: true)

    assert {:ok, second_plan} = HostKit.plan(project, opts)

    assert %HostKit.Change{action: :no_op} =
             Enum.find(second_plan.changes, &(&1.resource_id == {:source, :app}))
  end

  defp fixture_repo_uri, do: create_repo!().uri

  defp create_repo! do
    root = Path.join(System.tmp_dir!(), "hostkit-source-#{System.unique_integer([:positive])}")
    work = Path.join(root, "work")
    bare = Path.join(root, "repo.git")

    File.mkdir_p!(work)
    git!(work, ["init", "--initial-branch=main"])
    git!(work, ["config", "user.email", "hostkit@example.invalid"])
    git!(work, ["config", "user.name", "HostKit Test"])
    File.write!(Path.join(work, "README.md"), "hello\n")
    git!(work, ["add", "README.md"])
    git!(work, ["commit", "-m", "initial"])
    revision = git!(work, ["rev-parse", "HEAD"])
    git!(root, ["clone", "--bare", work, bare])

    on_exit(fn -> File.rm_rf(root) end)
    %{root: root, uri: bare, revision: revision}
  end

  defp git!(cwd, args) do
    case System.cmd("git", args, cd: cwd, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed with #{status}:\n#{output}")
    end
  end
end
