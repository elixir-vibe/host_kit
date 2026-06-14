defmodule HostKit.ReadinessTest do
  use ExUnit.Case, async: false

  test "ready DSL expands to readiness resource" do
    defmodule ReadyProject do
      use HostKit

      def project do
        project :ready_demo do
          service :app do
            package(:curl)

            ready :app do
              systemd("app.service", restart: true)
              http("http://127.0.0.1:4000/health", body: "ok")
            end
          end
        end
      end
    end

    assert Enum.any?(HostKit.Project.resources(ReadyProject.project()), fn
             %HostKit.Resources.Readiness{name: :app, checks: checks} ->
               match?(
                 [
                   %HostKit.Readiness.Systemd{unit: "app.service", restart: true},
                   %HostKit.Readiness.HTTP{url: "http://127.0.0.1:4000/health", expect_body: "ok"}
                 ],
                 checks
               )

             _resource ->
               false
           end)
  end

  test "readiness waits until checks pass" do
    readiness =
      HostKit.Resources.Readiness.new(:demo,
        checks: [HostKit.Readiness.HTTP.new("http://example.test", body: "ok")]
      )

    defmodule ReadyRunner do
      @behaviour HostKit.Runner

      @impl true
      def cmd("sh", ["-c", script], opts) do
        send(opts[:test_pid], {:readiness_script, script})
        {"", 0}
      end

      @impl true
      def mkdir_p(_path, _opts), do: :ok

      @impl true
      def write_file(_path, _content, _opts), do: :ok
    end

    assert :ok = HostKit.Readiness.wait(readiness, runner: {ReadyRunner, test_pid: self()})
    assert_received {:readiness_script, script}
    assert script =~ "curl"
    assert script =~ "grep -F 'ok'"
  end
end
