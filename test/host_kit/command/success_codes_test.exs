defmodule HostKit.CommandSuccessCodesTest do
  use ExUnit.Case, async: false

  alias HostKit.Resources.Command

  defmodule ExitRunner do
    @behaviour HostKit.Runner

    @impl true
    def cmd(command, ["-c", script], opts) when command == "sh" do
      send(opts[:test_pid], {:cmd, command, ["-c", script], opts})

      path =
        script
        |> String.replace_prefix("sudo base64 ", "")
        |> String.replace_prefix("base64 ", "")

      {path |> String.trim("'") |> File.read!() |> Base.encode64(), 0}
    end

    def cmd(command, args, opts) do
      send(opts[:test_pid], {:cmd, command, args, opts})
      output = if opts[:echo_args], do: Enum.join(args, " "), else: "exit"
      {output, opts[:exit_status] || 0}
    end

    @impl true
    def mkdir_p(_path, _opts), do: :ok

    @impl true
    def write_file(_path, _content, _opts), do: :ok
  end

  def handle_runner_start(_event, _measurements, metadata, test_pid) do
    send(test_pid, {:runner_start, metadata})
  end

  test "command success_codes accepts modeled non-zero statuses" do
    command =
      Command.new(:stop_unit, exec: {"systemctl", ["stop", "app.service"]}, success_codes: [0, 5])

    plan = %HostKit.Plan{
      changes: [
        %HostKit.Change{
          action: :create,
          resource_id: HostKit.Resource.id(command),
          after: command,
          reason: :missing
        }
      ]
    }

    assert {:ok, [%{status: :applied}]} =
             HostKit.Apply.run(plan,
               confirm: true,
               runner: {ExitRunner, test_pid: self(), exit_status: 5}
             )

    assert_received {:cmd, "systemctl", ["stop", "app.service"], _opts}
  end

  test "command failures, traces, and telemetry redact modeled env-file secrets" do
    test_pid = self()
    handler_id = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        [:host_kit, :runner, :cmd, :start],
        &__MODULE__.handle_runner_start/4,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    root =
      Path.join(
        System.tmp_dir!(),
        "host-kit-command-redaction-#{System.unique_integer([:positive])}"
      )

    env_path = Path.join(root, "app.env")
    File.mkdir_p!(root)
    File.write!(env_path, "PUBLIC=visible\nTOKEN=super-secret\n")
    on_exit(fn -> File.rm_rf(root) end)

    env_file = %HostKit.Resources.EnvFile{
      path: env_path,
      entries: [{:set, "PUBLIC", "visible"}, {:secret, "TOKEN", :redacted}]
    }

    command =
      Command.new(:migrate,
        exec: {"app", ["eval", "App.Release.migrate()"]},
        user: "app",
        env_files: [env_path]
      )

    plan = %HostKit.Plan{
      project: %HostKit.Project{name: :redaction_test, resources: [env_file]},
      changes: [
        %HostKit.Change{
          action: :create,
          resource_id: HostKit.Resource.id(command),
          after: command,
          reason: :missing
        }
      ]
    }

    assert {:error,
            {_resource_id, {:command_failed, "sudo", error_args, 9, error_output} = reason}} =
             HostKit.Apply.run(plan,
               confirm: true,
               sudo: true,
               trace: self(),
               runner: {ExitRunner, test_pid: self(), exit_status: 9, echo_args: true}
             )

    assert "PUBLIC=visible" in error_args
    assert "TOKEN=<redacted>" in error_args
    assert error_output =~ "PUBLIC=visible"
    assert error_output =~ "TOKEN=<redacted>"
    refute inspect(reason) =~ "super-secret"
    refute HostKit.Error.format(reason) =~ "super-secret"

    assert_received {:cmd, "sudo", executed_args, _opts}
    assert "TOKEN=super-secret" in executed_args

    assert_received {:hostkit_runner_trace, "sudo", trace_args, 9, _duration}
    assert "TOKEN=<redacted>" in trace_args
    refute inspect(trace_args) =~ "super-secret"

    assert_received {:runner_start, %{command: "sudo", args: telemetry_args}}
    assert "TOKEN=<redacted>" in telemetry_args
    refute inspect(telemetry_args) =~ "super-secret"
  end

  test "command user and env_files run with structured sudo env argv" do
    root =
      Path.join(System.tmp_dir!(), "host-kit-command-env-#{System.unique_integer([:positive])}")

    env_path = Path.join(root, "app.env")
    File.mkdir_p!(root)
    File.write!(env_path, ~s(FOO="from file"\nBAR="overridden"\n))
    on_exit(fn -> File.rm_rf(root) end)

    command =
      Command.new(:migrate,
        exec: {"/opt/app/bin/app", ["eval", "App.Release.migrate()"]},
        user: "app",
        env_files: [env_path],
        env: %{"BAR" => "explicit"}
      )

    plan = %HostKit.Plan{
      changes: [
        %HostKit.Change{
          action: :create,
          resource_id: HostKit.Resource.id(command),
          after: command,
          reason: :missing
        }
      ]
    }

    assert {:ok, [%{status: :applied}]} =
             HostKit.Apply.run(plan,
               confirm: true,
               sudo: true,
               runner: {ExitRunner, test_pid: self(), exit_status: 0}
             )

    assert_received {:cmd, "sudo",
                     [
                       "-u",
                       "app",
                       "-H",
                       "env",
                       "BAR=explicit",
                       "FOO=from file",
                       "/opt/app/bin/app",
                       "eval",
                       "App.Release.migrate()"
                     ], _opts}
  end
end
