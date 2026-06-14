defmodule HostKit.Integration.LivebookDeployPhoenixAppTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @tag timeout: 900_000
  test "deploys the Livebook Phoenix app notebook DSL" do
    case HostKit.IntegrationTarget.selected() do
      {:ok, target} ->
        with_telemetry_logging(fn -> deploy_notebook_dsl(target) end)

      {:skip, reason} ->
        IO.puts("Skipping Livebook deploy Phoenix app integration: #{reason}")
    end
  end

  defp with_telemetry_logging(fun) do
    handler_id = {__MODULE__, make_ref()}

    events = [
      [:host_kit, :plan, :stop],
      [:host_kit, :plan, :resource, :stop],
      [:host_kit, :apply, :stop],
      [:host_kit, :apply, :resource, :stop],
      [:host_kit, :runner, :cmd, :stop]
    ]

    :telemetry.attach_many(
      handler_id,
      events,
      &__MODULE__.handle_telemetry_event/4,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler_id)
    end
  end

  def handle_telemetry_event(event, measurements, metadata, _config) do
    IO.puts(format_telemetry_event(event, measurements, metadata))
  end

  defp format_telemetry_event([:host_kit | event], measurements, metadata) do
    duration = measurements[:duration] && HostKit.Telemetry.duration_ms(measurements.duration)
    label = event |> Enum.map_join(".", &to_string/1)

    "[hostkit:telemetry] #{label} #{duration || 0}ms #{format_telemetry_metadata(metadata)}"
  end

  defp format_telemetry_metadata(metadata) do
    metadata
    |> Map.take([:project, :phase, :resource_id, :action, :runner, :command, :status, :result])
    |> inspect()
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

    source_repo = timed("create source repo", fn -> create_source_repo!(host, unique) end)

    timed("cleanup previous deployment", fn -> cleanup.("/tmp/#{deployment_name}") end)

    on_exit(fn ->
      cleanup.("/tmp/#{deployment_name}")
      cleanup.(source_repo)
      File.rm_rf(source_repo)
      File.rm(artifact_path)
    end)

    project =
      timed("evaluate notebook DSL", fn ->
        eval_notebook_dsl(%{
          host: host,
          app_name: app_name,
          app_port: app_port,
          http_port: http_port,
          caddy_config_path: caddy_config_path,
          caddy_config_dir: caddy_config_dir,
          caddy_sites_dir: caddy_sites_dir,
          caddy_service_name: caddy_service_name,
          source_repo: source_repo
        })
      end)

    target_opts =
      project.hosts
      |> hd()
      |> HostKit.Host.target_opts()
      |> Keyword.put_new(
        :package_repo,
        System.get_env("HOSTKIT_INTEGRATION_PACKAGE_REPO", "ubuntu_24_04")
      )
      |> Keyword.put_new(:package_lock, "test/fixtures/package_locks/beam_apt.package.lock")
      |> maybe_trace_commands()

    {:ok, plan} = timed("plan", fn -> HostKit.plan(project, target_opts) end)

    assert :ok =
             timed("save plan artifact", fn -> HostKit.Plan.Artifact.save(artifact_path, plan) end)

    assert File.exists?(artifact_path)

    assert Enum.any?(
             plan.resources,
             &match?(%HostKit.Resources.Source{revision: revision} when is_binary(revision), &1)
           )

    assert Enum.any?(plan.resources, fn
             %HostKit.Caddy.Site{host: host} -> host == ":#{http_port}"
             _resource -> false
           end)

    reporter = start_apply_reporter()

    assert {:ok, _results} =
             timed("apply", fn ->
               HostKit.apply(plan, Keyword.merge(target_opts, confirm: true, reporter: reporter))
             end)

    send(reporter, :stop)

    runner = {HostKit.Runner.SSH, HostKit.Host.ssh_options(host) |> maybe_trace_commands()}

    timed("verify app service", fn ->
      assert {_, 0} = sudo_cmd(host, runner, ["systemctl", "restart", app_service_name])
      assert {:ok, "active\n"} = wait_until_active(host, runner, app_service_name, 80)
      assert {:ok, _health} = wait_until_http(runner, "http://127.0.0.1:#{app_port}/health", 80)
    end)

    timed("verify caddy service", fn ->
      assert {_, 0} = sudo_cmd(host, runner, ["systemctl", "restart", caddy_service_name])
      assert {:ok, "active\n"} = wait_until_active(host, runner, caddy_service_name, 40)
    end)

    assert {body, 0} =
             timed("verify public HTTP", fn ->
               HostKit.Runner.cmd(runner, "curl", ["-fsS", "http://127.0.0.1:#{http_port}"],
                 stderr_to_stdout: true
               )
             end)

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
      source_repo: opts.source_repo,
      source_ref: "main",
      erlang_version: System.get_env("HOSTKIT_INTEGRATION_ERLANG", "29.0.2"),
      elixir_version: System.get_env("HOSTKIT_INTEGRATION_ELIXIR", "1.20.1"),
      app_name: opts.app_name,
      app_port: opts.app_port,
      http_port: opts.http_port,
      app_service_name: "hello-phoenix.service",
      ingress_address: ":#{opts.http_port}",
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

  defp create_source_repo!(host, unique) do
    repo = "/tmp/hostkit-phoenix-source-#{unique}.git"
    work = Path.join(System.tmp_dir!(), "hostkit-phoenix-work-#{unique}")
    archive = Path.join(System.tmp_dir!(), "hostkit-phoenix-source-#{unique}.tgz")

    File.rm_rf!(work)
    File.rm_rf!(repo)
    File.rm(archive)
    File.mkdir_p!(Path.join(work, "examples"))
    File.cp_r!("examples/hello_phoenix", Path.join(work, "examples/hello_phoenix"))

    git!(work, ["init", "--initial-branch=main"])
    git!(work, ["config", "user.email", "hostkit@example.invalid"])
    git!(work, ["config", "user.name", "HostKit Test"])
    git!(work, ["add", "."])
    git!(work, ["commit", "-m", "initial"])
    git!(Path.dirname(repo), ["clone", "--bare", work, repo])

    {_, 0} = System.cmd("tar", ["-C", Path.dirname(repo), "-czf", archive, Path.basename(repo)])

    runner = {HostKit.Runner.SSH, HostKit.Host.ssh_options(host) |> maybe_trace_commands()}
    :ok = HostKit.Runner.write_file(runner, archive, File.read!(archive), [])
    assert {_, 0} = HostKit.Runner.cmd(runner, "rm", ["-rf", repo], stderr_to_stdout: true)

    assert {_, 0} =
             HostKit.Runner.cmd(runner, "tar", ["-C", Path.dirname(repo), "-xzf", archive],
               stderr_to_stdout: true
             )

    assert {_, 0} =
             sudo_cmd(host, runner, ["git", "config", "--global", "--add", "safe.directory", repo])

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

  defp wait_until_http(_runner, _url, 0), do: {:error, :not_ready}

  defp wait_until_http(runner, url, attempts) do
    case HostKit.Runner.cmd(runner, "curl", ["-fsS", url], stderr_to_stdout: true) do
      {body, 0} ->
        {:ok, body}

      _other ->
        Process.sleep(500)
        wait_until_http(runner, url, attempts - 1)
    end
  end

  defp timed(label, fun) do
    started = System.monotonic_time(:millisecond)
    IO.puts("[hostkit:integration] start #{label}")

    try do
      fun.()
    after
      duration = System.monotonic_time(:millisecond) - started
      IO.puts("[hostkit:integration] finish #{label} #{duration}ms")
    end
  end

  defp maybe_trace_commands(opts) do
    if System.get_env("HOSTKIT_TRACE_COMMANDS", "1") in ["1", "true", "yes"] do
      Keyword.put(opts, :trace, :stdio)
    else
      opts
    end
  end

  defp start_apply_reporter do
    parent = self()

    spawn_link(fn ->
      receive_apply_events(parent)
    end)
  end

  defp receive_apply_events(parent) do
    receive do
      {HostKit.Apply, event} ->
        send(parent, {:hostkit_apply_event, event})
        IO.puts("[hostkit:apply] #{HostKit.Apply.Event.format(event)}")
        receive_apply_events(parent)

      :stop ->
        :ok
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
