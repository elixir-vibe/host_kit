defmodule HostKit.BootstrapIntegrationTest do
  use HostKit.Case, async: false

  @moduletag :integration
  @moduletag :lima

  defmodule LimaRunner do
    @behaviour HostKit.Runner

    @impl true
    def cmd(command, args, opts) do
      vm = Keyword.get(opts, :vm, System.get_env("HOSTKIT_LIMA_VM", "hostkit-test"))

      System.cmd(limactl(), ["shell", vm, "--" | guest_command(command, args, opts)],
        stderr_to_stdout: true
      )
    end

    @impl true
    def mkdir_p(path, opts) do
      command = if Keyword.get(opts, :sudo, false), do: "sudo", else: "mkdir"
      args = if command == "sudo", do: ["mkdir", "-p", path], else: ["-p", path]

      case cmd(command, args, opts) do
        {_output, 0} -> :ok
        {output, status} -> {:error, {:command_failed, "mkdir", ["-p", path], status, output}}
      end
    end

    @impl true
    def write_file(path, content, opts) do
      vm = Keyword.get(opts, :vm, System.get_env("HOSTKIT_LIMA_VM", "hostkit-test"))

      command = if Keyword.get(opts, :sudo, false), do: ["sudo", "tee", path], else: ["tee", path]

      case System.cmd(limactl(), ["shell", vm, "--" | guest_command(command, opts)],
             input: IO.iodata_to_binary(content),
             stderr_to_stdout: true
           ) do
        {_output, 0} -> :ok
        {output, status} -> {:error, {:command_failed, "write_file", [path], status, output}}
      end
    end

    defp limactl, do: System.get_env("LIMACTL", "limactl")

    defp guest_command(command, args, opts) do
      guest_command([command | args], opts)
    end

    defp guest_command(command, opts) do
      env = Keyword.get(opts, :env, []) ++ [{"MISE_NO_CONFIG", "1"}]
      ["env" | Enum.map(env, fn {key, value} -> "#{key}=#{value}" end)] ++ command
    end
  end

  @tag timeout: 1_200_000
  test "HostKit installs packages and BEAM tools with mise on a Lima target" do
    vm = System.get_env("HOSTKIT_LIMA_VM", "hostkit-test")
    unique = System.unique_integer([:positive])
    mise_path = "/tmp/hostkit-integration/mise-#{unique}/bin/mise"
    system_data_dir = "/tmp/hostkit-integration/mise-#{unique}/share"

    cleanup(vm, Path.dirname(Path.dirname(mise_path)))

    assert {:ok, package_repo} =
             HostKit.Package.TargetRepo.detect(runner: {LimaRunner, vm: vm}, sudo: true)

    package_lock = %{package_lock_fixture() | target: package_repo}

    erlang_version = System.get_env("HOSTKIT_ERLANG_VERSION", "29.0.2")
    elixir_version = System.get_env("HOSTKIT_ELIXIR_VERSION", "1.20.1")

    project = %HostKit.Project{
      name: :bootstrap,
      services: [
        %HostKit.Service{
          name: :base,
          resources: [
            HostKit.Resources.Mise.new(
              path: mise_path,
              system_data_dir: system_data_dir,
              packages: :auto,
              tools: [
                %{name: :erlang, version: erlang_version, opts: []},
                %{name: :elixir, version: elixir_version, opts: []}
              ]
            )
          ]
        }
      ]
    }

    assert {:ok, plan} =
             HostKit.plan(project,
               reader: HostKit.Remote,
               runner: {LimaRunner, vm: vm},
               sudo: true,
               package_lock: package_lock,
               package_repo: package_repo
             )

    assert {:ok, results} =
             HostKit.apply(plan,
               confirm: true,
               runner: {LimaRunner, vm: vm},
               sudo: true
             )

    assert Enum.any?(results, &(&1.status == :applied))
    assert {_, 0} = LimaRunner.cmd("test", ["-x", mise_path], vm: vm)

    assert {version_output, 0} =
             LimaRunner.cmd(
               mise_path,
               [
                 "exec",
                 "erlang@#{erlang_version}",
                 "elixir@#{elixir_version}",
                 "--",
                 "elixir",
                 "--version"
               ],
               vm: vm,
               sudo: true,
               env: [{"MISE_NO_CONFIG", "1"}, {"MISE_SYSTEM_DATA_DIR", system_data_dir}]
             )

    assert version_output =~ elixir_version
  after
    vm = System.get_env("HOSTKIT_LIMA_VM", "hostkit-test")
    cleanup(vm, "/tmp/hostkit-integration")
  end

  defp package_lock_fixture do
    "package_locks/beam_apt.package.lock"
    |> fixture_path()
    |> HostKit.Package.Lock.load!()
  end

  defp cleanup(vm, path) do
    if System.find_executable(System.get_env("LIMACTL", "limactl")) do
      LimaRunner.cmd("rm", ["-rf", path], vm: vm)
    end

    :ok
  end
end
