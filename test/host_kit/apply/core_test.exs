defmodule HostKit.ApplyTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias HostKit.Apply
  alias HostKit.Change
  alias HostKit.Plan
  alias HostKit.Resources.{Account, Command, Directory, File, Readiness}
  alias HostKit.Systemd

  test "requires confirmation outside dry-run" do
    plan = %Plan{changes: []}

    assert Apply.run(plan) == {:error, :confirmation_required}
  end

  test "reports apply lifecycle messages" do
    path =
      Path.join(System.tmp_dir!(), "host-kit-apply-events-#{System.unique_integer([:positive])}")

    plan = %Plan{
      changes: [
        %Change{action: :no_op, resource_id: {:directory, "/already-there"}},
        %Change{
          action: :create,
          resource_id: {:directory, path},
          after: %Directory{path: path}
        }
      ]
    }

    assert {:ok, [%{status: :skipped}, %{status: :applied}]} =
             Apply.run(plan, confirm: true, reporter: self())

    assert_received {HostKit.Apply, %HostKit.Apply.Event{type: :apply_started}}

    assert_received {HostKit.Apply,
                     %HostKit.Apply.Event{
                       type: :change_skipped,
                       resource_id: {:directory, "/already-there"}
                     }}

    assert_received {HostKit.Apply,
                     %HostKit.Apply.Event{
                       type: :change_started,
                       resource_id: {:directory, ^path}
                     }}

    assert_received {HostKit.Apply,
                     %HostKit.Apply.Event{
                       type: :change_finished,
                       resource_id: {:directory, ^path}
                     }}

    assert_received {HostKit.Apply, %HostKit.Apply.Event{type: :apply_finished}}

    Elixir.File.rm_rf!(path)
  end

  test "orders apply changes by declared dependencies" do
    command = %Command{name: :prepare, exec: {"true", []}}

    readiness = %Readiness{
      name: :smoke,
      checks: [],
      depends_on: [{:command, :prepare}]
    }

    plan = %Plan{
      changes: [
        %Change{action: :create, resource_id: {:readiness, :smoke}, after: readiness},
        %Change{action: :create, resource_id: {:command, :prepare}, after: command}
      ]
    }

    assert {:ok, results} = Apply.run(plan, dry_run: true)

    assert Enum.map(results, & &1.change.resource_id) == [
             {:command, :prepare},
             {:readiness, :smoke}
           ]
  end

  test "dry-runs supported changes without touching filesystem" do
    path =
      Path.join(System.tmp_dir!(), "host-kit-apply-dry-run-#{System.unique_integer([:positive])}")

    plan = %Plan{
      changes: [
        %Change{
          action: :create,
          resource_id: {:directory, path},
          after: %Directory{path: path}
        }
      ]
    }

    assert {:ok, [%{status: :dry_run}]} = Apply.run(plan, dry_run: true)
    refute Elixir.File.exists?(path)
  end

  test "creates directories and files" do
    root = Path.join(System.tmp_dir!(), "host-kit-apply-#{System.unique_integer([:positive])}")
    dir = Path.join(root, "etc/app")
    file = Path.join(dir, "env")

    plan = %Plan{
      changes: [
        %Change{
          action: :create,
          resource_id: {:directory, dir},
          after: %Directory{path: dir, mode: 0o755}
        },
        %Change{
          action: :create,
          resource_id: {:file, file},
          after: %File{path: file, content: "PORT=4000\n", mode: 0o600}
        }
      ]
    }

    assert {:ok, [%{status: :applied}, %{status: :applied}]} = Apply.run(plan, confirm: true)
    assert Elixir.File.read!(file) == "PORT=4000\n"
    assert {:ok, %{mode: dir_mode}} = Elixir.File.stat(dir)
    assert {:ok, %{mode: file_mode}} = Elixir.File.stat(file)
    assert Bitwise.band(dir_mode, 0o777) == 0o755
    assert Bitwise.band(file_mode, 0o777) == 0o600

    Elixir.File.rm_rf!(root)
  end

  test "creates accounts through useradd" do
    account = %Account{
      name: "toys-demo",
      system: true,
      home: "/var/lib/toys/demo",
      shell: "/usr/sbin/nologin",
      groups: ["caddy"]
    }

    plan = %Plan{
      changes: [%Change{action: :create, resource_id: {:account, account.name}, after: account}]
    }

    parent = self()

    defmodule UseraddRunner do
      @behaviour HostKit.Runner

      @impl true
      def cmd(command, args, opts) do
        send(opts[:test_pid], {:cmd, command, args, Keyword.delete(opts, :test_pid)})
        {"", 0}
      end

      @impl true
      def mkdir_p(_path, _opts), do: :ok

      @impl true
      def write_file(_path, _content, _opts), do: :ok
    end

    assert {:ok, [%{status: :applied}]} =
             Apply.run(plan, confirm: true, runner: {UseraddRunner, test_pid: parent})

    assert_received {:cmd, "useradd",
                     [
                       "--system",
                       "--home",
                       "/var/lib/toys/demo",
                       "--shell",
                       "/usr/sbin/nologin",
                       "--groups",
                       "caddy",
                       "toys-demo"
                     ], [stderr_to_stdout: true]}
  end

  test "refuses account updates" do
    account = %Account{name: "toys-demo"}

    plan = %Plan{
      changes: [%Change{action: :update, resource_id: {:account, account.name}, after: account}]
    }

    assert {:error, {{:account, "toys-demo"}, :account_update_not_supported}} =
             Apply.run(plan, confirm: true)
  end

  test "writes systemd units and can skip daemon reload in tests" do
    root = Path.join(System.tmp_dir!(), "host-kit-systemd-#{System.unique_integer([:positive])}")

    service = %Systemd.Service{
      name: "demo.service",
      unit: [description: "Demo"],
      service: [exec_start: "/usr/bin/env true"],
      install: [wanted_by: "multi-user.target"]
    }

    timer = %Systemd.Timer{
      name: "demo.timer",
      unit: [description: "Demo timer"],
      timer: [on_boot_sec: "1min"],
      install: [wanted_by: "timers.target"]
    }

    plan = %Plan{
      changes: [
        %Change{action: :create, resource_id: {:systemd_service, service.name}, after: service},
        %Change{action: :create, resource_id: {:systemd_timer, timer.name}, after: timer}
      ]
    }

    assert {:ok, [%{status: :applied}, %{status: :applied}]} =
             Apply.run(plan,
               confirm: true,
               systemd_unit_dir: root,
               systemd_unit_owner: nil,
               systemd_unit_group: nil,
               systemd_daemon_reload: false
             )

    assert Elixir.File.read!(Path.join(root, "demo.service")) =~ "[Service]"
    assert Elixir.File.read!(Path.join(root, "demo.timer")) =~ "[Timer]"

    Elixir.File.rm_rf!(root)
  end

  test "retries initial ssh connection before apply starts" do
    connect_fun = fn _host, _port, _ssh_opts, _timeout -> {:error, :econnrefused} end
    plan = %Plan{changes: []}

    capture_log(fn ->
      assert {:error, {:ssh_connect_failed, :econnrefused}} =
               Apply.run(plan,
                 confirm: true,
                 reporter: self(),
                 runner:
                   {HostKit.Runner.SSH,
                    host: "example.test",
                    user: "root",
                    connect_fun: connect_fun,
                    retry: [attempts: 2, base_delay: 0]}
               )
    end)

    assert_receive {HostKit.Apply, %HostKit.Apply.Event{type: :transport_retry_started}}
    assert_receive {HostKit.Apply, %HostKit.Apply.Event{type: :transport_retry_exhausted}}
    refute_received {HostKit.Apply, %HostKit.Apply.Event{type: :apply_started}}
  end

  test "stops at first runner transport failure and reports the failed change" do
    first = "/tmp/hostkit-first"
    second = "/tmp/hostkit-second"

    plan = %Plan{
      changes: [
        %Change{
          action: :create,
          resource_id: {:directory, first},
          after: %Directory{path: first}
        },
        %Change{
          action: :create,
          resource_id: {:directory, second},
          after: %Directory{path: second}
        }
      ]
    }

    defmodule FlakyRunner do
      @behaviour HostKit.Runner

      @impl true
      def mkdir_p(path, opts) do
        attempt = Agent.get_and_update(opts[:attempts], fn count -> {count, count + 1} end)
        send(opts[:test_pid], {:mkdir_p, path, attempt})

        case attempt do
          0 -> :ok
          _ -> {:error, {:ssh_connect_failed, :closed}}
        end
      end

      @impl true
      def cmd(_command, _args, _opts), do: {"", 0}

      @impl true
      def write_file(_path, _content, _opts), do: :ok
    end

    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    assert {:error, {{:directory, ^second}, {:ssh_connect_failed, :closed}}} =
             Apply.run(plan,
               confirm: true,
               reporter: self(),
               runner: {FlakyRunner, attempts: attempts, test_pid: self()}
             )

    assert_received {:mkdir_p, ^first, 0}
    assert_received {:mkdir_p, ^second, 1}

    assert_received {HostKit.Apply,
                     %HostKit.Apply.Event{
                       type: :change_finished,
                       resource_id: {:directory, ^first}
                     }}

    assert_received {HostKit.Apply,
                     %HostKit.Apply.Event{
                       type: :change_failed,
                       resource_id: {:directory, ^second},
                       reason: {:ssh_connect_failed, :closed}
                     }}

    refute_received {HostKit.Apply, %HostKit.Apply.Event{type: :apply_finished}}
  end

  test "refuses to write redacted files" do
    plan = %Plan{
      changes: [
        %Change{
          action: :update,
          resource_id: {:file, "/tmp/redacted"},
          after: %File{path: "/tmp/redacted", content: :redacted}
        }
      ]
    }

    assert {:error, {{:file, "/tmp/redacted"}, :file_content_managed_elsewhere}} =
             Apply.run(plan, confirm: true)
  end
end
