defmodule HostKit.BootstrapIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  defmodule LimaRunner do
    @behaviour HostKit.Runner

    @impl true
    def cmd(command, args, opts) do
      vm = Keyword.get(opts, :vm, System.get_env("HOSTKIT_LIMA_VM", "hostkit-test"))

      System.cmd(limactl(), ["shell", vm, "--", command | args],
        stderr_to_stdout: true,
        env: env()
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

      case System.cmd(limactl(), ["shell", vm, "--" | command],
             input: IO.iodata_to_binary(content),
             stderr_to_stdout: true,
             env: env()
           ) do
        {_output, 0} -> :ok
        {output, status} -> {:error, {:command_failed, "write_file", [path], status, output}}
      end
    end

    defp limactl, do: System.get_env("LIMACTL", "limactl")

    defp env do
      [{"MISE_IGNORED_CONFIG_PATHS", "/Users/dannote/.config/mise/config.toml"}]
    end
  end

  test "HostKit installs packages and mise on a Lima target" do
    vm = System.get_env("HOSTKIT_LIMA_VM", "hostkit-test")
    unique = System.unique_integer([:positive])
    mise_path = "/tmp/hostkit-integration/mise-#{unique}/bin/mise"
    system_data_dir = "/tmp/hostkit-integration/mise-#{unique}/share"

    cleanup(vm, Path.dirname(Path.dirname(mise_path)))

    project = %HostKit.Project{
      name: :bootstrap,
      services: [
        %HostKit.Service{
          name: :base,
          resources: [
            HostKit.Resources.Package.new(:ca_certificates, as: "ca-certificates"),
            HostKit.Resources.Mise.new(
              path: mise_path,
              system_data_dir: system_data_dir,
              packages: false,
              tools: []
            )
          ]
        }
      ]
    }

    assert {:ok, plan} =
             HostKit.plan(project,
               reader: HostKit.Remote,
               runner: {LimaRunner, vm: vm},
               sudo: true
             )

    assert {:ok, results} =
             HostKit.apply(plan,
               confirm: true,
               runner: {LimaRunner, vm: vm},
               sudo: true
             )

    assert Enum.any?(results, &(&1.status == :applied))
    assert {_, 0} = LimaRunner.cmd("test", ["-x", mise_path], vm: vm)
  after
    vm = System.get_env("HOSTKIT_LIMA_VM", "hostkit-test")
    cleanup(vm, "/tmp/hostkit-integration")
  end

  defp cleanup(vm, path) do
    LimaRunner.cmd("rm", ["-rf", path], vm: vm)
    :ok
  end
end
