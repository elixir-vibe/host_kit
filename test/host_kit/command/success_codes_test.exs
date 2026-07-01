defmodule HostKit.CommandSuccessCodesTest do
  use ExUnit.Case, async: true

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
      {"exit", opts[:exit_status] || 0}
    end

    @impl true
    def mkdir_p(_path, _opts), do: :ok

    @impl true
    def write_file(_path, _content, _opts), do: :ok
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
