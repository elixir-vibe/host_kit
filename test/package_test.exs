defmodule HostKit.PackageTest do
  use ExUnit.Case, async: true

  defmodule Runner do
    @behaviour HostKit.Runner

    def cmd("sh", ["-c", "dpkg-query" <> _rest], _opts), do: {"installed\t1.2.3", 0}

    def cmd("sh", ["-c", "command -v apt-get >/dev/null 2>&1"] = args, opts) do
      send(opts[:test_pid], {:cmd, "sh", args})
      {"", 0}
    end

    def cmd(command, args, opts) do
      send(opts[:test_pid], {:cmd, command, args})
      {"", 0}
    end

    def mkdir_p(_path, _opts), do: :ok
    def write_file(_path, _content, _opts), do: :ok
  end

  defmodule Reader do
    def read(resource, %{opts: opts}) do
      case Keyword.fetch!(opts, :installed) do
        true ->
          {:ok, %{resource | meta: %{installed: true, version: Keyword.get(opts, :version)}}}

        false ->
          {:ok, nil}
      end
    end
  end

  test "package DSL builds distro-agnostic package resources" do
    source = """
    use HostKit.DSL

    project :demo do
      service :bootstrap do
        package :ca_certificates
        package :build_essential, as: "build-essential", update: true
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [ca, build] = HostKit.Project.resources(project)
    assert %HostKit.Resources.Package{name: :ca_certificates, system_name: "ca-certificates"} = ca

    assert %HostKit.Resources.Package{system_name: "build-essential", update: true} = build
  end

  test "package resources install through selected manager" do
    package = HostKit.Resources.Package.new(:curl, update: true)

    plan = %HostKit.Plan{
      project: %HostKit.Project{name: :demo},
      changes: [
        %HostKit.Change{
          action: :create,
          resource_id: HostKit.Resources.Package.id(package),
          after: package
        }
      ]
    }

    assert {:ok, _results} =
             HostKit.apply(plan,
               confirm: true,
               package_manager: :apt,
               runner: {Runner, test_pid: self()}
             )

    assert_received {:cmd, "sh", ["-c", command]}

    assert command =~
             "DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y -- 'curl'"
  end

  test "apply batches consecutive package installs" do
    packages = [HostKit.Resources.Package.new(:curl), HostKit.Resources.Package.new(:git)]

    plan = %HostKit.Plan{
      project: %HostKit.Project{name: :demo},
      changes:
        Enum.map(packages, fn package ->
          %HostKit.Change{
            action: :create,
            resource_id: HostKit.Resources.Package.id(package),
            after: package
          }
        end)
    }

    assert {:ok, results} =
             HostKit.apply(plan,
               confirm: true,
               package_manager: :apt,
               runner: {Runner, test_pid: self()}
             )

    assert [_curl_result, _git_result] = results
    commands = receive_commands([])
    assert "DEBIAN_FRONTEND=noninteractive apt-get install -y -- 'curl' 'git'" in commands
    refute "DEBIAN_FRONTEND=noninteractive apt-get install -y -- 'curl'" in commands
    refute "DEBIAN_FRONTEND=noninteractive apt-get install -y -- 'git'" in commands
  end

  test "apply detects package manager once for package changes" do
    packages = [HostKit.Resources.Package.new(:curl), HostKit.Resources.Package.new(:git)]

    plan = %HostKit.Plan{
      project: %HostKit.Project{name: :demo},
      changes:
        Enum.map(packages, fn package ->
          %HostKit.Change{
            action: :create,
            resource_id: HostKit.Resources.Package.id(package),
            after: package
          }
        end)
    }

    assert {:ok, _results} =
             HostKit.apply(plan, confirm: true, runner: {Runner, test_pid: self()})

    assert_received {:cmd, "sh", ["-c", "command -v apt-get >/dev/null 2>&1"]}
    refute_received {:cmd, "sh", ["-c", "command -v dnf >/dev/null 2>&1"]}
  end

  defp receive_commands(commands) do
    receive do
      {:cmd, "sh", ["-c", command]} -> receive_commands([command | commands])
      {:cmd, _command, _args} -> receive_commands(commands)
    after
      0 -> Enum.reverse(commands)
    end
  end

  test "package resources read installed state from package manager" do
    package = HostKit.Resources.Package.new(:curl)

    assert {:ok, actual} =
             HostKit.Package.read(package, %{opts: [package_manager: :apt, runner: Runner]})

    assert actual.meta.installed == true
    assert actual.meta.version == "1.2.3"
  end

  test "package resources plan as no-op only when installed" do
    package = HostKit.Resources.Package.new(:curl)

    project = %HostKit.Project{
      name: :demo,
      services: [%HostKit.Service{name: :bootstrap, resources: [package]}]
    }

    assert {:ok, missing_plan} = HostKit.plan(project, reader: Reader, installed: false)
    assert [%HostKit.Change{action: :create}] = missing_plan.changes

    assert {:ok, synced_plan} = HostKit.plan(project, reader: Reader, installed: true)
    assert [%HostKit.Change{action: :no_op}] = synced_plan.changes
  end
end
