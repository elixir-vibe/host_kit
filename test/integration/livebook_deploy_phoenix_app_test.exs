defmodule HostKit.Integration.LivebookDeployPhoenixAppTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @tag timeout: 900_000
  test "deploys the Livebook Phoenix app notebook DSL" do
    case HostKit.IntegrationTarget.selected() do
      {:ok, target} ->
        deploy_notebook_dsl(target)

      {:skip, reason} ->
        IO.puts("Skipping Livebook deploy Phoenix app integration: #{reason}")
    end
  end

  defp deploy_notebook_dsl(%HostKit.IntegrationTarget{host: host, cleanup: cleanup}) do
    unique = System.unique_integer([:positive])
    app_name = :hello_phoenix
    app_service_name = "hello-phoenix.service"
    app_port = 14_000 + rem(unique, 1000)
    http_port = 19_000 + rem(unique, 1000)
    deployment_name = "hostkit-phoenix-integration-#{unique}"
    caddy_config_path = "/tmp/#{deployment_name}/Caddyfile"
    caddy_config_dir = Path.dirname(caddy_config_path)
    caddy_sites_dir = "/tmp/#{deployment_name}/sites"
    caddy_service_name = "#{deployment_name}.service"
    artifact_path = Path.join(System.tmp_dir!(), "#{deployment_name}.plan.json")

    cleanup.("/tmp/#{deployment_name}")

    on_exit(fn ->
      cleanup.("/tmp/#{deployment_name}")
      File.rm(artifact_path)
    end)

    project =
      eval_notebook_dsl(%{
        host: host,
        app_name: app_name,
        app_port: app_port,
        http_port: http_port,
        caddy_config_path: caddy_config_path,
        caddy_config_dir: caddy_config_dir,
        caddy_sites_dir: caddy_sites_dir,
        caddy_service_name: caddy_service_name
      })

    target_opts = HostKit.Host.target_opts(hd(project.hosts))

    {:ok, plan} = HostKit.plan(project, target_opts)
    assert :ok = HostKit.Plan.Artifact.save(artifact_path, plan)
    assert File.exists?(artifact_path)

    assert Enum.any?(
             plan.resources,
             &match?(%HostKit.Resources.Source{revision: revision} when is_binary(revision), &1)
           )

    assert {:ok, _results} = HostKit.apply(plan, Keyword.merge(target_opts, confirm: true))

    runner = {HostKit.Runner.SSH, HostKit.Host.ssh_options(host)}

    assert {_, 0} = sudo_cmd(host, runner, ["systemctl", "restart", app_service_name])
    assert {:ok, "active\n"} = wait_until_active(host, runner, app_service_name, 80)

    assert {_, 0} = sudo_cmd(host, runner, ["systemctl", "restart", caddy_service_name])
    assert {:ok, "active\n"} = wait_until_active(host, runner, caddy_service_name, 40)

    assert {body, 0} =
             HostKit.Runner.cmd(runner, "curl", ["-fsS", "http://127.0.0.1:#{http_port}"],
               stderr_to_stdout: true
             )

    assert body =~ "Hello Phoenix from HostKit"

    assert {health, 0} =
             HostKit.Runner.cmd(runner, "curl", ["-fsS", "http://127.0.0.1:#{app_port}/health"],
               stderr_to_stdout: true
             )

    assert health =~ "ok"
  end

  defp eval_notebook_dsl(%{host: host} = opts) do
    binding = [
      target_host: host.hostname,
      target_user: host.user,
      target_sudo: host.sudo,
      ssh_opts: host.meta[:ssh] || [],
      public_hostname: "phoenix.example.test",
      source_ref: "master",
      app_name: opts.app_name,
      app_port: opts.app_port,
      http_port: opts.http_port,
      app_service_name: "hello-phoenix.service",
      site_address: ":#{opts.http_port}",
      caddy_config_path: opts.caddy_config_path,
      caddy_config_dir: opts.caddy_config_dir,
      caddy_sites_dir: opts.caddy_sites_dir,
      caddy_service_name: opts.caddy_service_name,
      caddyfile: """
      {
        admin off
      }

      import #{opts.caddy_sites_dir}/*.caddy
      """,
      secret_key_base: Base.encode64(:crypto.strong_rand_bytes(64))
    ]

    {project, _binding} = Code.eval_string(notebook_dsl!(), binding)
    project
  end

  defp wait_until_active(host, runner, service_name, attempts)
  defp wait_until_active(_host, _runner, _service_name, 0), do: {:error, :not_active}

  defp wait_until_active(host, runner, service_name, attempts) do
    case sudo_cmd(host, runner, ["systemctl", "is-active", service_name]) do
      {"active\n", 0} ->
        {:ok, "active\n"}

      _other ->
        Process.sleep(500)
        wait_until_active(host, runner, service_name, attempts - 1)
    end
  end

  defp sudo_cmd(%HostKit.Host{sudo: true}, runner, [command | args]) do
    HostKit.Runner.cmd(runner, "sudo", [command | args], stderr_to_stdout: true)
  end

  defp sudo_cmd(_host, runner, [command | args]) do
    HostKit.Runner.cmd(runner, command, args, stderr_to_stdout: true)
  end

  defp notebook_dsl! do
    content = File.read!("notebooks/learn/deploy_phoenix_app.livemd")
    regex = ~r/```elixir\n(?<source>[^`]*# hostkit:deploy-phoenix-app-dsl.*?)\n```/s

    case Regex.run(regex, content, capture: ["source"]) do
      [source] -> source
      nil -> raise "could not find marked HostKit DSL cell in deploy_phoenix_app.livemd"
    end
  end
end
