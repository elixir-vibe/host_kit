defmodule HostKit.Integration.LivebookDeployCaddySiteTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @tag timeout: 300_000
  test "deploys the Livebook Caddy site notebook DSL" do
    case HostKit.IntegrationTarget.selected() do
      {:ok, target} ->
        deploy_notebook_dsl(target)

      {:skip, reason} ->
        IO.puts("Skipping Livebook deploy Caddy site integration: #{reason}")
    end
  end

  defp deploy_notebook_dsl(%HostKit.IntegrationTarget{host: host, cleanup: cleanup}) do
    unique = System.unique_integer([:positive])
    root = "/tmp/hostkit-livebook-caddy-#{unique}"
    site_root = Path.join(root, "site")
    caddy_config_path = Path.join(root, "Caddyfile")
    caddy_sites_dir = Path.join(root, "caddy-sites")
    caddy_service_name = "hostkit-livebook-caddy-#{unique}.service"
    port = 18_000 + rem(unique, 1000)
    artifact_path = Path.join(System.tmp_dir!(), "hostkit-livebook-caddy-#{unique}.plan.json")

    cleanup.(root)

    on_exit(fn ->
      cleanup.(root)
      File.rm(artifact_path)
    end)

    project =
      eval_notebook_dsl(
        host,
        site_root,
        caddy_config_path,
        caddy_sites_dir,
        caddy_service_name,
        port,
        unique
      )

    target_opts = HostKit.Host.target_opts(hd(project.hosts))

    {:ok, plan} = HostKit.plan(project, target_opts)
    assert :ok = HostKit.Plan.Artifact.save(artifact_path, plan)
    assert File.exists?(artifact_path)

    assert {:ok, _results} = HostKit.apply(plan, Keyword.merge(target_opts, confirm: true))

    runner = {HostKit.Runner.SSH, HostKit.Host.ssh_options(host)}

    assert {_, 0} =
             HostKit.Runner.cmd(runner, "test", ["-f", Path.join(site_root, "index.html")],
               stderr_to_stdout: true
             )

    assert {_, 0} =
             HostKit.Runner.cmd(runner, "test", ["-f", Path.join(caddy_sites_dir, "hello.caddy")],
               stderr_to_stdout: true
             )

    assert {_, 0} = sudo_cmd(host, runner, ["systemctl", "restart", caddy_service_name])

    assert {"active\n", 0} =
             sudo_cmd(host, runner, ["systemctl", "is-active", caddy_service_name])

    assert {body, 0} =
             HostKit.Runner.cmd(runner, "curl", ["-fsS", "http://127.0.0.1:#{port}"],
               stderr_to_stdout: true
             )

    assert body =~ "Integration #{unique}"
  end

  defp eval_notebook_dsl(
         host,
         site_root,
         caddy_config_path,
         caddy_sites_dir,
         caddy_service_name,
         port,
         unique
       ) do
    binding = [
      target_host: host.hostname,
      target_user: host.user,
      target_sudo: host.sudo,
      ssh_opts: host.meta[:ssh] || [],
      site_address: ":#{port}",
      site_root: site_root,
      caddy_config_path: caddy_config_path,
      caddy_config_dir: Path.dirname(caddy_config_path),
      caddy_sites_dir: caddy_sites_dir,
      caddy_service_name: caddy_service_name,
      message: "Integration #{unique}"
    ]

    {project, _binding} = Code.eval_string(notebook_dsl!(), binding)
    project
  end

  defp sudo_cmd(%HostKit.Host{sudo: true}, runner, [command | args]) do
    HostKit.Runner.cmd(runner, "sudo", [command | args], stderr_to_stdout: true)
  end

  defp sudo_cmd(_host, runner, [command | args]) do
    HostKit.Runner.cmd(runner, command, args, stderr_to_stdout: true)
  end

  defp notebook_dsl! do
    content = File.read!("notebooks/learn/deploy_caddy_site.livemd")

    regex = ~r/```elixir\n(?<source>[^`]*# hostkit:deploy-caddy-site-dsl.*?)\n```/s

    case Regex.run(regex, content, capture: ["source"]) do
      [source] -> source
      nil -> raise "could not find marked HostKit DSL cell in deploy_caddy_site.livemd"
    end
  end
end
