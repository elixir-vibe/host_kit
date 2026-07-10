defmodule HostKit.Integration.LivebookDeployCaddySiteTest do
  use ExUnit.Case, async: false
  require HostKit.IntegrationCase

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

    runner = {HostKit.Runner.SSH, HostKit.Host.ssh_options(host)}

    HostKit.IntegrationCase.on_exit_rollback(plan, target_opts,
      only: [{:systemd_service, caddy_service_name}],
      before_rollback: fn -> sudo_cmd(host, runner, ["systemctl", "stop", caddy_service_name]) end
    )

    assert :ok = HostKit.Plan.Artifact.save(artifact_path, plan)
    assert File.exists?(artifact_path)

    assert {:ok, _results} = HostKit.apply(plan, Keyword.merge(target_opts, confirm: true))

    assert {_, 0} =
             HostKit.Runner.cmd(runner, "test", ["-f", Path.join(site_root, "index.html")],
               stderr_to_stdout: true
             )

    assert {_, 0} =
             HostKit.Runner.cmd(runner, "test", ["-f", Path.join(caddy_sites_dir, "hello.caddy")],
               stderr_to_stdout: true
             )

    assert {_, 0} = sudo_cmd(host, runner, ["systemctl", "restart", caddy_service_name])
    assert {:ok, "active\n"} = wait_until_active(host, runner, caddy_service_name)

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
      target: %{
        host: host.hostname,
        user: host.user,
        sudo: host.sudo,
        ssh: host.meta[:ssh] || []
      },
      site_address: ":#{port}",
      acme_email: "admin@example.test",
      site_root: site_root,
      caddy_config_path: caddy_config_path,
      caddy_config_dir: Path.dirname(caddy_config_path),
      caddy_sites_dir: caddy_sites_dir,
      caddy_service_name: caddy_service_name,
      verify_url: "http://#{host.hostname}:#{port}",
      message: "Integration #{unique}"
    ]

    {project, _binding} = Code.eval_string(notebook_dsl!(), binding)
    project
  end

  defp wait_until_active(host, runner, service_name, attempts \\ 20)

  defp wait_until_active(_host, _runner, _service_name, 0), do: {:error, :not_active}

  defp wait_until_active(host, runner, service_name, attempts) do
    case sudo_cmd(host, runner, ["systemctl", "is-active", service_name]) do
      {"active\n", 0} ->
        {:ok, "active\n"}

      _other ->
        Process.sleep(250)
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
    source =
      HostKit.LivebookNotebook.code_cell_containing!(
        "notebooks/learn/deploy_caddy_site.livemd",
        "project :deploy_caddy_site do"
      )

    "alias HostKit, as: HK\nalias HostKit.Providers.Caddy\n" <> source
  end
end
