defmodule HostKit.MiseTest do
  use ExUnit.Case, async: true

  defmodule Runner do
    @behaviour HostKit.Runner

    def cmd("sh", ["-c", "test -x " <> _path], opts) do
      send(opts[:test_pid], {:cmd, "sh", ["-c", "test -x ..."]})
      {"missing", 1}
    end

    def cmd(command, args, opts) do
      send(opts[:test_pid], {:cmd, command, args})
      {"", 0}
    end

    def mkdir_p(path, opts) do
      send(opts[:test_pid], {:mkdir_p, path})
      :ok
    end

    def write_file(path, content, opts) do
      send(opts[:test_pid], {:write_file, path, content})
      :ok
    end
  end

  defmodule ReadRunner do
    @behaviour HostKit.Runner

    def cmd("sh", ["-c", "test -x " <> _path], _opts), do: {"", 0}

    def cmd("sh", ["-c", command], _opts) do
      if command =~ "where 'erlang@29.0.2'", do: {"/mise/erlang\n", 0}, else: {"missing", 1}
    end

    def mkdir_p(_path, _opts), do: :ok
    def write_file(_path, _content, _opts), do: :ok
  end

  defmodule Reader do
    def read(resource, %{opts: opts}) do
      installed_tools = Keyword.fetch!(opts, :installed_tools)
      {:ok, %{resource | meta: Map.put(resource.meta, :installed_tools, installed_tools)}}
    end
  end

  test "mise DSL builds installable tool resources" do
    source = """
    use HostKit.DSL

    project :demo do
      service :bootstrap do
        mise path: "/usr/local/bin/mise", system_data_dir: "/usr/local/share/mise" do
          tool :erlang, "29.0.2"
          tool :elixir, "1.20.1"
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert resources = HostKit.Project.resources(project)
    assert %HostKit.Resources.Mise{} = resource = List.last(resources)

    assert Enum.map(resource.tools, &{&1.name, &1.version}) == [
             erlang: "29.0.2",
             elixir: "1.20.1"
           ]
  end

  test "mise resources expand prerequisite packages" do
    mise =
      HostKit.Resources.Mise.new()
      |> HostKit.Resources.Mise.add_tool(:erlang, "29.0.2")

    package_names = mise |> HostKit.Resources.Mise.package_resources() |> Enum.map(& &1.name)

    assert :curl in package_names
    assert :ca_certificates in package_names
    assert :openssl_dev in package_names
    assert :ncurses_dev in package_names
    assert :cxx_compiler in package_names
  end

  test "mise package expansion supports explicit modes" do
    disabled = HostKit.Resources.Mise.new(packages: false)
    assert HostKit.Resources.Mise.package_resources(disabled) == []

    common = HostKit.Resources.Mise.new(packages: :common)

    assert Enum.map(HostKit.Resources.Mise.package_resources(common), & &1.name) == [
             :curl,
             :ca_certificates
           ]

    custom = HostKit.Resources.Mise.new(packages: [:curl, :custom_dep])

    assert Enum.map(HostKit.Resources.Mise.package_resources(custom), & &1.name) == [
             :curl,
             :custom_dep
           ]
  end

  test "project resources place mise prerequisites before mise" do
    mise =
      HostKit.Resources.Mise.new()
      |> HostKit.Resources.Mise.add_tool(:erlang, "29.0.2")

    project = %HostKit.Project{
      name: :demo,
      services: [%HostKit.Service{name: :bootstrap, resources: [mise]}]
    }

    resources = HostKit.Project.resources(project)

    assert %HostKit.Resources.Package{name: :curl} = hd(resources)
    assert %HostKit.Resources.Mise{} = List.last(resources)
  end

  test "mise CLI read reports installed tools" do
    mise = mise_resource()

    assert {:ok, actual} = HostKit.Mise.read(mise, %{opts: [runner: ReadRunner]})
    assert actual.meta.installed_tools == [erlang: "29.0.2"]
  end

  test "mise resources plan as update until every requested tool is installed" do
    mise = mise_resource()

    project = %HostKit.Project{
      name: :demo,
      services: [%HostKit.Service{name: :bootstrap, resources: [mise]}]
    }

    assert {:ok, update_plan} =
             HostKit.plan(project,
               reader: Reader,
               installed_tools: [erlang: "29.0.2"]
             )

    assert [%HostKit.Change{action: :update}] = update_plan.changes

    assert {:ok, synced_plan} =
             HostKit.plan(project,
               reader: Reader,
               installed_tools: [erlang: "29.0.2", elixir: "1.20.1"]
             )

    assert [%HostKit.Change{action: :no_op}] = synced_plan.changes
  end

  test "mise resources bootstrap mise and install system tools" do
    mise = mise_resource()

    plan = %HostKit.Plan{
      project: %HostKit.Project{name: :demo},
      changes: [
        %HostKit.Change{
          action: :create,
          resource_id: HostKit.Resources.Mise.id(mise),
          after: mise
        }
      ]
    }

    assert {:ok, _results} =
             HostKit.apply(plan, confirm: true, runner: {Runner, test_pid: self()})

    assert_received {:cmd, "sh", ["-c", "test -x ..."]}
    assert_received {:cmd, "sh", ["-c", install_cmd]}
    assert install_cmd =~ "curl -fsSL https://mise.run"
    assert_received {:mkdir_p, "/usr/local/share/mise"}
    assert_received {:cmd, "sh", ["-c", tools_cmd]}
    assert tools_cmd =~ "MISE_SYSTEM_DATA_DIR='/usr/local/share/mise'"
    assert tools_cmd =~ "'/usr/local/bin/mise' install --system 'erlang@29.0.2' 'elixir@1.20.1'"
  end

  defp mise_resource do
    %HostKit.Resources.Mise{
      path: "/usr/local/bin/mise",
      system_data_dir: "/usr/local/share/mise",
      packages: false,
      tools: [
        %{name: :erlang, version: "29.0.2", opts: []},
        %{name: :elixir, version: "1.20.1", opts: []}
      ]
    }
  end
end
