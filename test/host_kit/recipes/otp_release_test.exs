defmodule HostKit.OTPReleaseRecipeTest do
  use HostKit.Case, async: true

  test "otp_release recipe expands artifact manifest to ordinary resources" do
    manifest_path = write_manifest!("demo_app", "abc123")

    defmodule OTPReleaseRecipeProject do
      use HostKit.DSL, recipes: [HostKit.Recipes.OTPRelease]

      def project(manifest_path) do
        project :demo do
          roots(opt: "/opt/example", config: "/etc/example")

          otp_release(:demo_app,
            manifest: manifest_path,
            port: 4100,
            base_dir: "/opt/example/demo_app",
            config_dir: "/etc/example/demo_app",
            account_home: "/var/lib/demo_app/home",
            env: %{"EXTRA_SETTING" => "enabled"}
          ) do
            listen(:rpc, protocol: :rpc)
          end
        end
      end
    end

    project = OTPReleaseRecipeProject.project(manifest_path)
    resources = HostKit.Project.resources(project)
    assert [service] = project.services

    assert %HostKit.Endpoint{port: 4100, protocol: :http, health: "/health"} =
             service.meta.endpoints.http

    assert %HostKit.Listener{protocol: :rpc} = service.meta.listeners.rpc

    assert Enum.any?(
             resources,
             &match?(
               %HostKit.Resources.Account{name: "demo-app", home: "/var/lib/demo_app/home"},
               &1
             )
           )

    assert Enum.any?(resources, fn
             %HostKit.Resources.EnvFile{path: "/etc/example/demo_app/env", entries: entries} ->
               {:set, "PHX_HOST", "app.example.com"} in entries and
                 {:set, "EXTRA_SETTING", "enabled"} in entries

             _resource ->
               false
           end)

    assert Enum.any?(resources, fn
             %HostKit.Resources.Command{
               name: "demo_app_unpack",
               exec: {"bash", ["-euo", "pipefail", "-c", command]},
               creates: "/opt/example/demo_app/releases/abc123/bin/demo_app",
               down: :irreversible,
               meta: %{otp_release_artifact: ^manifest_path}
             } ->
               command =~ "tar -xzf '/tmp/demo_app-abc123.tar.gz'"

             _resource ->
               false
           end)

    assert Enum.any?(resources, fn
             %HostKit.Resources.Symlink{
               path: "/opt/example/demo_app/current",
               to: "/opt/example/demo_app/releases/abc123",
               depends_on: [{:command, "demo_app_unpack"}]
             } ->
               true

             _resource ->
               false
           end)

    assert Enum.any?(resources, fn
             %HostKit.Systemd.Service{name: "demo-app.service", service: service} ->
               service |> Keyword.fetch!(:exec_start) |> List.wrap() |> hd() ==
                 "/opt/example/demo_app/current/bin/demo_app start"

             _resource ->
               false
           end)

    assert Enum.any?(resources, fn
             %HostKit.Resources.Readiness{name: "demo_app_ready", checks: checks} ->
               match?(
                 [
                   %HostKit.Readiness.Systemd{unit: "demo-app.service", restart: true},
                   %HostKit.Readiness.HTTP{url: "http://127.0.0.1:4100/health"}
                 ],
                 checks
               )

             _resource ->
               false
           end)
  end

  test "collects and builds ReleaseKit artifacts through HostKit runner boundary" do
    tmp =
      Path.join(System.tmp_dir!(), "hostkit-release-kit-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(tmp) end)

    app = Path.join(tmp, "app")
    File.mkdir_p!(app)

    manifest_path = Path.join(app, "_build/prod/artifacts/demo_app.etf")
    File.mkdir_p!(Path.dirname(manifest_path))
    File.write!(manifest_path, :erlang.term_to_binary(valid_manifest("demo_app", "built123")))

    config = Path.join(tmp, "config.exs")

    File.write!(config, """
    defmodule ReleaseKitCollectProject do
      use HostKit.DSL, recipes: [HostKit.Recipes.OTPRelease]

      project :demo do
        roots opt: "/opt/example", config: "/etc/example"

        otp_release :demo_app,
          release_kit: [cwd: #{inspect(app)}],
          base_dir: "/opt/example/demo_app",
          config_dir: "/etc/example/demo_app"
      end
    end
    """)

    artifacts = HostKit.Recipes.OTPRelease.collect_release_kit(config)

    assert [artifact] = artifacts
    assert artifact.cwd == app
    assert artifact.out_dir == "_build/prod/artifacts"
    assert artifact.mix_env == "prod"
    assert artifact.manifest == manifest_path

    test_pid = self()

    runner =
      Module.concat(
        __MODULE__,
        "ReleaseKitRunner#{System.unique_integer([:positive]) |> abs()}"
      )

    Module.create(
      runner,
      quote do
        @behaviour HostKit.Runner

        def cmd(command, args, opts) do
          send(unquote(Macro.escape(test_pid)), {:release_kit_cmd, command, args, opts})
          {"", 0}
        end

        def mkdir_p(_path, _opts), do: :ok
        def write_file(_path, _content, _opts), do: :ok
      end,
      Macro.Env.location(__ENV__)
    )

    HostKit.Recipes.OTPRelease.build_release_kit_artifacts!(artifacts, runner: runner)

    assert_receive {:release_kit_cmd, "mix",
                    ["release_kit.artifact", "--out-dir", "_build/prod/artifacts"], opts}

    assert Keyword.fetch!(opts, :cd) == app
    assert Keyword.fetch!(opts, :env) == %{"MIX_ENV" => "prod"}
  end

  test "otp_release rejects non-OTP release manifests" do
    path =
      Path.join(System.tmp_dir!(), "hostkit-invalid-#{System.unique_integer([:positive])}.etf")

    File.write!(path, :erlang.term_to_binary(%{format: :other}))

    assert_raise ArgumentError, ~r/not an OTP release artifact/, fn ->
      HostKit.Recipes.OTPRelease.load_manifest!(path)
    end
  end

  defp write_manifest!(release_name, version) do
    path = Path.join(System.tmp_dir!(), "hostkit-otp-#{System.unique_integer([:positive])}.etf")

    File.write!(path, :erlang.term_to_binary(valid_manifest(release_name, version)))
    path
  end

  defp valid_manifest(release_name, version) do
    %{
      tool: "example",
      format: :beam_release_artifact,
      format_version: 1,
      app: release_name,
      version: version,
      release: release_name,
      mix_env: "prod",
      tarball: "/tmp/#{release_name}-#{version}.tar.gz",
      runtime: %{command: ["bin/#{release_name}", "start"]},
      env: %{clear: %{"PHX_HOST" => "app.example.com"}, secret: ["SECRET_KEY_BASE"]},
      health_check: %{path: "/health", port: 4100, url: "http://127.0.0.1:4100/health"}
    }
  end
end
