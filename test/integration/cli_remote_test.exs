defmodule HostKit.CLIRemoteIntegrationTest do
  use HostKit.Case, async: false

  import ExUnit.CaptureIO

  @moduletag :integration

  @tag timeout: 300_000
  test "plans and applies a remote plan artifact over SSH" do
    case HostKit.IntegrationTarget.selected() do
      {:ok, target} ->
        run_remote_cli_integration(target)

      {:skip, reason} ->
        IO.puts("Skipping remote CLI integration: #{reason}")
    end
  end

  defp run_remote_cli_integration(%HostKit.IntegrationTarget{
         host: host,
         cleanup: cleanup,
         verify: verify
       }) do
    unique = System.unique_integer([:positive])
    root = "/tmp/hostkit-cli-integration-#{unique}"
    mise_path = "#{root}/bin/mise"
    data_dir = "#{root}/share"
    config_path = Path.join(System.tmp_dir!(), "hostkit-cli-#{unique}.exs")
    plan_path = Path.join(System.tmp_dir!(), "hostkit-cli-#{unique}.plan.json")
    lock_path = fixture_path("package_locks/beam_apt.package.lock")

    cleanup.(root)

    on_exit(fn ->
      cleanup.(root)
      File.rm(config_path)
      File.rm(plan_path)
      Mix.Task.reenable("host_kit.plan")
      Mix.Task.reenable("host_kit.apply")
    end)

    File.write!(config_path, project_source(host, mise_path, data_dir))

    plan_args = [
      "--host",
      to_string(host.name),
      "--package-lock",
      lock_path,
      "--out",
      plan_path,
      config_path
    ]

    apply_args = ["--host", to_string(host.name), "--plan", plan_path, "--confirm", config_path]

    capture_io(fn -> Mix.Tasks.HostKit.Plan.run(plan_args) end)
    assert File.exists?(plan_path)

    capture_io(fn -> Mix.Tasks.HostKit.Apply.run(apply_args) end)
    assert {_, 0} = verify.(mise_path)
  end

  defp project_source(host, mise_path, data_dir) do
    host_name = host.name
    hostname = host.hostname
    user = host.user
    sudo = host.sudo
    ssh_opts = host.meta[:ssh] || []

    quote do
      use HostKit.DSL

      project :cli_bootstrap do
        host unquote(host_name), at: unquote(hostname) do
          ssh(
            Keyword.merge(unquote(Macro.escape(ssh_opts)),
              user: unquote(user),
              sudo: unquote(sudo)
            )
          )
        end

        service :base do
          package(:ca_certificates)

          mise path: unquote(mise_path), system_data_dir: unquote(data_dir), packages: false do
          end
        end
      end
    end
    |> Macro.to_string()
    |> Kernel.<>("\n")
  end
end
