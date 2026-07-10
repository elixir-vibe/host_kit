defmodule HostKit.MonitorRunTest do
  use ExUnit.Case, async: true

  defmodule Runner do
    @behaviour HostKit.Runner

    @impl true
    def cmd("systemctl", ["is-active", "web.service"], opts) do
      send(opts[:test_pid], {:systemctl, opts})
      {"active\n", 0}
    end

    def cmd("systemctl", ["is-active", "failed.service"], _opts), do: {"failed\n", 3}

    def cmd("/usr/local/sbin/check", ["--fast"], opts) do
      send(opts[:test_pid], {:command_check, opts})
      {"ok\n", 0}
    end

    def cmd("/usr/local/sbin/fail", [], _opts), do: {"boom\n", 2}

    def cmd("sudo", ["/usr/local/sbin/check", "--fast"], opts) do
      send(opts[:test_pid], {:sudo_command_check, opts})
      {"ok\n", 0}
    end

    @impl true
    def mkdir_p(_path, _opts), do: :ok

    @impl true
    def write_file(_path, _content, _opts), do: :ok
  end

  test "runs systemd checks through runner" do
    project =
      project_with_check(
        HostKit.Monitor.check(:systemd, resource_id: {:systemd_service, "web.service"})
      )

    assert {:ok, [result]} =
             HostKit.Monitor.run(project, runner: Runner, runner_opts: [test_pid: self()])

    assert result.status == :ok
    assert result.observed.state == :active
    assert_received {:systemctl, opts}
    assert opts[:stderr_to_stdout] == true
  end

  test "reports failing systemd checks" do
    project = project_with_check(HostKit.Monitor.check(:systemd, unit: "failed.service"))

    assert {:ok, [result]} = HostKit.Monitor.run(project, runner: Runner)
    assert result.status == :error
    assert result.reason == {:unexpected_state, "failed"}
  end

  test "runs command checks through runner" do
    project =
      project_with_check(
        HostKit.Monitor.check(:command,
          exec: HostKit.CommandLine.argv("/usr/local/sbin/check", args: ["--fast"]),
          expect: [exit: 0]
        )
      )

    assert {:ok, [result]} =
             HostKit.Monitor.run(project, runner: Runner, runner_opts: [test_pid: self()])

    assert result.status == :ok
    assert result.observed.exit == 0
    assert result.observed.output == "ok\n"
    assert_received {:command_check, opts}
    assert opts[:stderr_to_stdout] == true
  end

  test "runs command checks through sudo when target opts request it" do
    project =
      project_with_check(
        HostKit.Monitor.check(:command,
          exec: HostKit.CommandLine.argv("/usr/local/sbin/check", args: ["--fast"]),
          expect: [exit: 0]
        )
      )

    target = HostKit.Target.local(:local, sudo: true)

    assert {:ok, [result]} =
             HostKit.Monitor.run(project,
               target: target,
               runner: Runner,
               runner_opts: [test_pid: self()]
             )

    assert result.status == :ok
    assert_received {:sudo_command_check, opts}
    assert opts[:stderr_to_stdout] == true
  end

  test "reports failing command checks" do
    project =
      project_with_check(
        HostKit.Monitor.check(:command, exec: ["/usr/local/sbin/fail"], expect: [exit: 0])
      )

    assert {:ok, [result]} = HostKit.Monitor.run(project, runner: Runner)
    assert result.status == :error
    assert result.reason == {:unexpected_exit, 0, 2}
    assert result.observed.output == "boom\n"
  end

  test "runs HTTP checks through Req" do
    adapter = fn request -> {request, Req.Response.new(status: 204, body: "ignored")} end

    project =
      project_with_check(
        HostKit.Monitor.check(:http, url: "https://example.test", expect: [status: 204])
      )

    assert {:ok, [result]} =
             HostKit.Monitor.run(project, req_options: [adapter: adapter])

    assert result.status == :ok
    assert result.observed.status == 204
  end

  test "runs filesystem checks" do
    path = Path.join(System.tmp_dir!(), "host-kit-monitor-#{System.unique_integer([:positive])}")
    File.write!(path, "ok")

    project = project_with_check(HostKit.Monitor.check(:filesystem, target: path))

    assert {:ok, [result]} = HostKit.Monitor.run(project)
    assert result.status == :ok
    assert result.observed.path == path

    File.rm!(path)
  end

  test "reports unsupported checks" do
    project = project_with_check(HostKit.Monitor.check(:custom, name: :custom))

    assert {:ok, [result]} = HostKit.Monitor.run(project)
    assert result.status == :error
    assert result.reason == {:unsupported_check_type, :custom}
  end

  defp project_with_check(check) do
    resource = HostKit.Resources.Directory.new("/tmp/example", meta: %{monitor: [check]})
    service = HostKit.Service.new(:demo, resources: [resource])
    HostKit.Project.new(:demo) |> HostKit.Project.add_service(service)
  end
end
