defmodule HostKit.Integration.GatehouseDeployTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @tag timeout: 1_200_000
  test "deploys Gatehouse release and starts systemd service" do
    if System.get_env("HOSTKIT_GATEHOUSE_DEPLOY_INTEGRATION") == "1" do
      case HostKit.IntegrationTarget.selected() do
        {:ok, target} -> deploy_gatehouse(target)
        {:skip, reason} -> IO.puts("Skipping Gatehouse deploy integration: #{reason}")
      end
    else
      IO.puts("Skipping Gatehouse deploy integration: set HOSTKIT_GATEHOUSE_DEPLOY_INTEGRATION=1")
    end
  end

  defp deploy_gatehouse(%HostKit.IntegrationTarget{host: host, cleanup: cleanup}) do
    unique = System.unique_integer([:positive])
    http_port = 18_500 + rem(unique, 1000)
    root = "/tmp/hostkit-gatehouse-deploy-#{unique}"
    release_path = Path.join(root, "release")
    config_path = Path.join(root, "config/config.exs")
    state_path = Path.join(root, "state/state.etf")
    env_path = Path.join(root, "env")
    service_unit = "hostkit-gatehouse-#{unique}.service"
    source_repo = create_source_repo!(host, unique)

    cleanup.(root)

    on_exit(fn ->
      runner = {HostKit.Runner.SSH, HostKit.Host.ssh_options(host)}
      sudo_cmd(host, runner, ["systemctl", "stop", service_unit])
      cleanup.(root)
      cleanup.(source_repo)
    end)

    project =
      Code.eval_string("""
      use HostKit.DSL, providers: [HostKit.Providers.Gatehouse]

      project :gatehouse_deploy do
        host :target do
          hostname #{inspect(host.hostname)}
          user #{inspect(host.user)}
          sudo #{inspect(host.sudo)}
          ssh #{inspect(host.meta[:ssh] || [])}
        end

        account :gatehouse, system: true, home: #{inspect(Path.dirname(state_path))}

        gatehouse_release :edge,
          source: [git: #{inspect(source_repo)}, path: "gatehouse", ref: "main"],
          release_path: #{inspect(release_path)}

        proxy :edge, provider: :gatehouse, path: #{inspect(config_path)} do
          state #{inspect(state_path)}
          http port: #{http_port}

          service :app do
            host "gatehouse.example.test"
            target :main, url: "http://127.0.0.1:9", active: true
          end
        end

        gatehouse :edge,
          release_path: #{inspect(release_path)},
          config_path: #{inspect(config_path)},
          state_path: #{inspect(state_path)},
          env_path: #{inspect(env_path)},
          service_unit: #{inspect(service_unit)},
          run_as: account(:gatehouse)
      end
      """)
      |> elem(0)

    target_opts =
      host
      |> HostKit.Host.target_opts()
      |> Keyword.put_new(
        :package_repo,
        System.get_env("HOSTKIT_INTEGRATION_PACKAGE_REPO", "ubuntu_24_04")
      )

    assert {:ok, plan} = HostKit.plan(project, target_opts)
    assert {:ok, _results} = HostKit.apply(plan, Keyword.merge(target_opts, confirm: true))

    runner = {HostKit.Runner.SSH, HostKit.Host.ssh_options(host)}
    assert {:ok, "active\n"} = wait_until_active(host, runner, service_unit, 120)
  end

  defp create_source_repo!(host, unique) do
    workspace = Path.expand("..", File.cwd!())
    work = Path.join(System.tmp_dir!(), "hostkit-gatehouse-source-#{unique}")
    archive = Path.join(System.tmp_dir!(), "hostkit-gatehouse-source-#{unique}.tgz")
    repo = "/tmp/hostkit-gatehouse-source-#{unique}.git"

    File.rm_rf!(work)
    File.rm(archive)
    File.mkdir_p!(work)

    for dir <- ["gatehouse", "safe_rpc", "systemdkit"] do
      assert {_, 0} =
               System.cmd(
                 "rsync",
                 [
                   "-a",
                   "--exclude",
                   ".git",
                   "--exclude",
                   "_build",
                   "--exclude",
                   "deps",
                   Path.join(workspace, dir) <> "/",
                   Path.join(work, dir) <> "/"
                 ],
                 stderr_to_stdout: true
               )
    end

    git!(work, ["init", "--initial-branch=main"])
    git!(work, ["config", "user.email", "hostkit@example.invalid"])
    git!(work, ["config", "user.name", "HostKit Test"])
    git!(work, ["add", "."])
    git!(work, ["commit", "-m", "gatehouse source"])
    git!(Path.dirname(work), ["clone", "--bare", work, repo])

    assert {_, 0} =
             System.cmd("tar", ["-C", Path.dirname(repo), "-czf", archive, Path.basename(repo)],
               stderr_to_stdout: true
             )

    runner = {HostKit.Runner.SSH, HostKit.Host.ssh_options(host)}
    :ok = HostKit.Runner.write_file(runner, archive, File.read!(archive), [])
    assert {_, 0} = HostKit.Runner.cmd(runner, "rm", ["-rf", repo], stderr_to_stdout: true)

    assert {_, 0} =
             HostKit.Runner.cmd(runner, "tar", ["-C", Path.dirname(repo), "-xzf", archive],
               stderr_to_stdout: true
             )

    File.rm_rf!(work)
    File.rm(archive)
    repo
  end

  defp git!(cwd, args) do
    case System.cmd("git", args, cd: cwd, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> raise "git #{Enum.join(args, " ")} failed with #{status}:\n#{output}"
    end
  end

  defp wait_until_active(_host, _runner, _service_name, 0), do: {:error, :not_active}

  defp wait_until_active(host, runner, service_name, attempts) do
    case sudo_cmd(host, runner, ["systemctl", "is-active", service_name]) do
      {"active\n", 0} ->
        {:ok, "active\n"}

      _other ->
        Process.sleep(1_000)
        wait_until_active(host, runner, service_name, attempts - 1)
    end
  end

  defp sudo_cmd(%HostKit.Host{sudo: true}, runner, [command | args]) do
    HostKit.Runner.cmd(runner, "sudo", [command | args], stderr_to_stdout: true)
  end

  defp sudo_cmd(_host, runner, [command | args]) do
    HostKit.Runner.cmd(runner, command, args, stderr_to_stdout: true)
  end
end
