defmodule HostKit.Integration.GatehouseDeployTest do
  use ExUnit.Case, async: false
  require HostKit.IntegrationCase

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
    account_name = "hk-gh-#{rem(unique, 100_000)}"
    mode = System.get_env("HOSTKIT_GATEHOUSE_DEPLOY_MODE", "source")
    runner = {HostKit.Runner.SSH, HostKit.Host.ssh_options(host)}
    source_repo = if mode == "source", do: create_source_repo!(host, unique), else: nil

    cleanup.(root)

    if mode == "prebuilt" do
      create_prebuilt_release!(host, release_path, unique)
    end

    on_exit(fn ->
      sudo_cmd(host, runner, ["systemctl", "stop", service_unit])
      cleanup.(root)
      if source_repo, do: cleanup.(source_repo)
    end)

    project =
      project(%{
        host: host,
        mode: mode,
        source_repo: source_repo,
        release_path: release_path,
        config_path: config_path,
        state_path: state_path,
        env_path: env_path,
        service_unit: service_unit,
        account_name: account_name,
        http_port: http_port
      })

    target_opts =
      host
      |> HostKit.Host.target_opts()
      |> Keyword.put_new(
        :package_repo,
        System.get_env("HOSTKIT_INTEGRATION_PACKAGE_REPO", "ubuntu_24_04")
      )
      |> Keyword.put_new(:package_lock, "test/fixtures/package_locks/beam_apt.package.lock")

    assert {:ok, plan} = HostKit.plan(project, target_opts)

    down_plan =
      HostKit.IntegrationCase.on_exit_rollback(plan, target_opts,
        only: [
          {:proxy, :web},
          {:systemd_service, service_unit}
        ],
        before_rollback: fn -> sudo_cmd(host, runner, ["systemctl", "stop", service_unit]) end
      )

    assert Enum.map(down_plan.changes, & &1.resource_id) == [
             {:systemd_service, service_unit},
             {:proxy, :web}
           ]

    assert {:ok, _dry_run} = HostKit.apply(down_plan, Keyword.merge(target_opts, dry_run: true))
    assert {:ok, _results} = HostKit.apply(plan, Keyword.merge(target_opts, confirm: true))

    assert {:ok, "active\n"} = wait_until_active(host, runner, service_unit, 120)
  end

  defp project(%{
         host: host,
         mode: mode,
         source_repo: source_repo,
         release_path: release_path,
         config_path: config_path,
         state_path: state_path,
         env_path: env_path,
         service_unit: service_unit,
         account_name: account_name,
         http_port: http_port
       }) do
    Code.eval_string("""
    use HostKit.DSL, providers: [HostKit.Providers.Gatehouse]

    project :gatehouse_deploy do
      host :target do
        hostname #{inspect(host.hostname)}
        user #{inspect(host.user)}
        sudo #{inspect(host.sudo)}
        ssh #{inspect(host.meta[:ssh] || [])}
      end

      account #{inspect(account_name)}, system: true, home: #{inspect(Path.dirname(state_path))}

      #{gatehouse_release_dsl(mode, source_repo, release_path)}

      service :edge do
        ingress :web, path: #{inspect(config_path)}, state: #{inspect(state_path)} do
          server ":#{http_port}" do
            route host: "gatehouse.example.test" do
              proxy to: "http://127.0.0.1:9"
            end
          end
        end
      end

      gatehouse :edge,
        release_path: #{inspect(release_path)},
        config_path: #{inspect(config_path)},
        state_path: #{inspect(state_path)},
        env_path: #{inspect(env_path)},
        service_unit: #{inspect(service_unit)},
        run_as: #{inspect(account_name)}
    end
    """)
    |> elem(0)
  end

  defp gatehouse_release_dsl("source", source_repo, release_path) do
    """
    gatehouse_release :edge,
      source: [git: #{inspect(source_repo)}, path: "gatehouse", ref: "main"],
      release_path: #{inspect(release_path)}
    """
  end

  defp gatehouse_release_dsl(_mode, _source_repo, _release_path), do: ""

  defp create_prebuilt_release!(host, release_path, unique) do
    gatehouse = Path.expand("../gatehouse", File.cwd!())
    archive = Path.join(System.tmp_dir!(), "hostkit-gatehouse-release-#{unique}.tgz")

    File.rm(archive)

    mix!(gatehouse, ["deps.get"], [{"MIX_ENV", "prod"}])
    mix!(gatehouse, ["deps.compile"], [{"MIX_ENV", "prod"}])
    mix!(gatehouse, ["release", "--overwrite"], [{"MIX_ENV", "prod"}])

    release_dir = Path.join(gatehouse, "_build/prod/rel/gatehouse")

    assert {_, 0} =
             System.cmd("tar", ["-C", release_dir, "-czf", archive, "."], stderr_to_stdout: true)

    runner = {HostKit.Runner.SSH, HostKit.Host.ssh_options(host)}
    remote_archive = "/tmp/#{Path.basename(archive)}"
    upload_file!(host, archive, remote_archive)

    assert {_, 0} =
             sudo_cmd(host, runner, [
               "sh",
               "-c",
               "set -eu; rm -rf #{HostKit.Shell.escape(release_path)}; mkdir -p #{HostKit.Shell.escape(release_path)}; tar -C #{HostKit.Shell.escape(release_path)} -xzf #{HostKit.Shell.escape(remote_archive)}"
             ])

    File.rm(archive)
  end

  defp mix!(cwd, args, env) do
    env =
      Keyword.merge(
        [MIX_ENV: "dev"],
        Enum.map(env, fn {key, value} -> {String.to_atom(key), value} end)
      )

    env = Enum.map(env, fn {key, value} -> {Atom.to_string(key), value} end)

    case System.cmd("mix", args, cd: cwd, env: env, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> raise "mix #{Enum.join(args, " ")} failed with #{status}:\n#{output}"
    end
  end

  defp create_source_repo!(host, unique) do
    workspace = Path.expand("..", File.cwd!())
    work = Path.join(System.tmp_dir!(), "hostkit-gatehouse-source-#{unique}")
    archive = Path.join(System.tmp_dir!(), "hostkit-gatehouse-source-#{unique}.tgz")
    repo = "/tmp/hostkit-gatehouse-source-#{unique}.git"

    HostKit.SafeTmp.rm_rf!(work, "hostkit-gatehouse-source-")
    HostKit.SafeTmp.rm_rf!(repo, "hostkit-gatehouse-source-")
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
    upload_file!(host, archive, archive)
    assert {_, 0} = HostKit.Runner.cmd(runner, "rm", ["-rf", repo], stderr_to_stdout: true)

    assert {_, 0} =
             HostKit.Runner.cmd(runner, "tar", ["-C", Path.dirname(repo), "-xzf", archive],
               stderr_to_stdout: true
             )

    assert {_, 0} =
             sudo_cmd(host, runner, ["git", "config", "--global", "--add", "safe.directory", repo])

    HostKit.SafeTmp.rm_rf!(work, "hostkit-gatehouse-source-")
    File.rm(archive)
    repo
  end

  defp upload_file!(host, local_path, remote_path) do
    ssh = host.meta[:ssh] || []

    args =
      []
      |> add_scp_option("-P", ssh[:port])
      |> add_scp_option("-i", ssh[:identity_file])
      |> Kernel.++([
        "-o",
        "StrictHostKeyChecking=accept-new",
        local_path,
        "#{host.user}@#{host.hostname}:#{remote_path}"
      ])

    case System.cmd("scp", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> raise "scp failed with #{status}:\n#{output}"
    end
  end

  defp add_scp_option(args, _option, nil), do: args
  defp add_scp_option(args, option, value), do: args ++ [option, to_string(value)]

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
