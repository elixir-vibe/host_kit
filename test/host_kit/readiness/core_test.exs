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

  test "ready DSL validates options through DSL option schemas" do
    assert_raise ArgumentError, ~r/unknown option :bad for readiness_opts at nofile:4/, fn ->
      Code.eval_string("""
      use HostKit.DSL

      project :demo do
        ready :app, bad: true do
        end
      end
      """)
    end

    assert_raise ArgumentError,
                 ~r/unknown option :bad for systemd_check_opts at nofile:5/,
                 fn ->
                   Code.eval_string("""
                   use HostKit.DSL

                   project :demo do
                     ready :app do
                       systemd "app.service", bad: true
                     end
                   end
                   """)
                 end

    assert_raise ArgumentError, ~r/unknown option :bad for http_check_opts at nofile:5/, fn ->
      Code.eval_string("""
      use HostKit.DSL

      project :demo do
        ready :app do
          http "http://127.0.0.1:4000/health", bad: true
        end
      end
      """)
    end
  end

  test "readiness waits until checks pass" do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen_socket)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        {:ok, _request} = :gen_tcp.recv(socket, 0)
        :ok = :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\nok")
        :gen_tcp.close(socket)
        :gen_tcp.close(listen_socket)
      end)

    readiness =
      HostKit.Resources.Readiness.new(:demo,
        checks: [HostKit.Readiness.HTTP.new("http://127.0.0.1:#{port}", body: "ok")]
      )

    assert :ok = HostKit.Readiness.wait(readiness, [])
    assert :ok = Task.await(server)
  end
end
