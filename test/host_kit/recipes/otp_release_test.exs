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
            before_start :migrate do
              eval(DemoApp.ReleaseTasks.migrate())
            end

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
                 {:set, "EXTRA_SETTING", "enabled"} in entries and
                 {:secret, "SECRET_KEY_BASE", :redacted} in entries

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
               owner: nil,
               group: nil,
               depends_on: [{:command, "demo_app_unpack"}]
             } ->
               true

             _resource ->
               false
           end)

    assert Enum.any?(resources, fn
             %HostKit.Resources.Command{
               name: "demo_app_migrate",
               phase: :before_start,
               depends_on: [
                 {:command, "demo_app_unpack"},
                 {:symlink, "/opt/example/demo_app/current"}
               ],
               inputs: ["/opt/example/demo_app/releases/abc123"],
               exec: {"sh", ["-c", migrate]}
             } ->
               migrate =~ "systemctl stop 'demo-app.service'" and
                 migrate =~ "sudo -u 'demo-app' -H sh -c" and
                 migrate =~ "'/opt/example/demo_app/current/bin/demo_app'" and
                 migrate =~ "DemoApp.ReleaseTasks.migrate()"

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
             %HostKit.Resources.Readiness{
               name: "demo_app_ready",
               checks: checks,
               depends_on: [{:command, "demo_app_migrate"}]
             } ->
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

  test "otp_release service selectors match release name aliases" do
    manifest_path = write_manifest!("incant", "abc123")

    defmodule OTPReleaseAliasProject do
      use HostKit.DSL, recipes: [HostKit.Recipes.OTPRelease]

      def project(manifest_path) do
        project :demo do
          roots(opt: "/opt/example", config: "/etc/example")

          otp_release(:incant,
            service: :incant_admin,
            manifest: manifest_path,
            path: "incant-admin"
          )
        end
      end
    end

    project = OTPReleaseAliasProject.project(manifest_path)

    assert {:ok, [:incant_admin]} = HostKit.Project.resolve_services(project, [:incant])
    assert {:ok, [:incant_admin]} = HostKit.Project.resolve_services(project, [:incant_admin])
    assert {:ok, [:incant_admin]} = HostKit.Project.resolve_services(project, ["incant"])
    assert {:ok, [:incant_admin]} = HostKit.Project.resolve_services(project, ["incant-admin"])

    assert [_resource | _] = HostKit.Project.resources(project, services: [:incant])
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

        otp_release :other_app,
          release_kit: [cwd: #{inspect(app)}],
          base_dir: "/opt/example/other_app",
          config_dir: "/etc/example/other_app"

        otp_release :incant,
          service: :incant_admin,
          release_kit: [cwd: #{inspect(app)}],
          base_dir: "/opt/example/incant-admin",
          config_dir: "/etc/example/incant-admin"
      end
    end
    """)

    artifacts = HostKit.Recipes.OTPRelease.collect_release_kit(config, services: [:demo_app])

    assert [artifact] = artifacts
    assert artifact.cwd == app
    assert artifact.service_name == :demo_app
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

    assert [%{name: :incant, service_name: :incant_admin}] =
             HostKit.Recipes.OTPRelease.collect_release_kit(config, services: [:incant])

    assert [%{name: :incant, service_name: :incant_admin}] =
             HostKit.Recipes.OTPRelease.collect_release_kit(config, services: [:incant_admin])

    HostKit.Recipes.OTPRelease.build_release_kit_artifacts!(artifacts, runner: runner)

    assert_receive {:release_kit_cmd, "mix",
                    ["release_kit.artifact", "--out-dir", "_build/prod/artifacts"], opts}

    assert Keyword.fetch!(opts, :cd) == app
    assert Keyword.fetch!(opts, :env) == %{"MIX_ENV" => "prod"}
  end

  test "builds ReleaseKit preparation project from existing source and command resources" do
    app =
      Path.join(
        System.tmp_dir!(),
        "hostkit-release-kit-prep-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(app, "lib"))
    File.write!(Path.join(app, "mix.exs"), "defmodule Demo.MixProject do end")
    File.write!(Path.join(app, "mix.lock"), "%{}")

    artifact = %{
      name: :demo_app,
      service_name: :demo_app,
      cwd: app,
      manifest: Path.join(app, "_build/prod/artifacts/demo_app.etf"),
      user: "deploy",
      mix_env: "prod",
      out_dir: "_build/prod/artifacts",
      timeout: 300_000
    }

    project = %HostKit.Project{
      name: :demo,
      meta: %{firewall: :ignored_for_prepare},
      services: [
        %HostKit.Service{
          name: :demo_app,
          resources: [
            HostKit.Resources.Package.new(:git, as: "git"),
            HostKit.Resources.Source.new(:demo_app,
              git: "https://example.test/demo.git",
              ref: "main",
              checkout: app
            )
          ]
        }
      ]
    }

    prepare_project = HostKit.Recipes.OTPRelease.prepare_project(project, [artifact])
    resources = HostKit.Project.resources(prepare_project)

    refute Map.has_key?(prepare_project.meta, :firewall)
    assert Enum.any?(resources, &match?(%HostKit.Resources.Source{name: :demo_app}, &1))

    assert %HostKit.Resources.Command{
             name: "demo_app_release_kit_deps",
             exec:
               {"sudo",
                ["-u", "deploy", "-H", "env", "MIX_ENV=prod", "mix", "deps.get", "--only", "prod"]},
             env: %{},
             cwd: ^app,
             inputs: [:demo_app, "mix.exs", "mix.lock"],
             outputs: ["deps"],
             meta: %{release_kit_artifact: manifest, target_opts: [sudo: false]}
           } =
             Enum.find(
               resources,
               &match?(%HostKit.Resources.Command{name: "demo_app_release_kit_deps"}, &1)
             )

    assert %HostKit.Resources.Command{
             name: "demo_app_release_kit_artifact",
             exec:
               {"sudo",
                [
                  "-u",
                  "deploy",
                  "-H",
                  "env",
                  "MIX_ENV=prod",
                  "mix",
                  "release_kit.artifact",
                  "--out-dir",
                  "_build/prod/artifacts"
                ]},
             env: %{},
             cwd: ^app,
             inputs: [:demo_app, "mix.exs", "mix.lock", "lib"],
             outputs: ["_build/prod/artifacts/demo_app.etf"],
             depends_on: [{:command, "demo_app_release_kit_deps"}],
             meta: %{release_kit_artifact: ^manifest, target_opts: [sudo: false]}
           } =
             Enum.find(
               resources,
               &match?(%HostKit.Resources.Command{name: "demo_app_release_kit_artifact"}, &1)
             )

    assert manifest == artifact.manifest

    no_user = HostKit.Recipes.OTPRelease.prepare_project(project, [%{artifact | user: nil}])

    no_user_artifact =
      no_user
      |> HostKit.Project.resources()
      |> Enum.find(&match?(%HostKit.Resources.Command{name: "demo_app_release_kit_artifact"}, &1))

    assert %HostKit.Resources.Command{
             exec: {"mix", ["release_kit.artifact", "--out-dir", "_build/prod/artifacts"]},
             env: %{"MIX_ENV" => "prod"},
             meta: %{release_kit_artifact: ^manifest}
           } = no_user_artifact
  end

  test "ReleaseKit build failures include command context" do
    test_pid = self()
    runner = Module.concat(__MODULE__, "FailingReleaseKitRunner")

    unless Code.ensure_loaded?(runner) do
      Module.create(
        runner,
        quote do
          @behaviour HostKit.Runner

          def cmd(command, args, opts) do
            send(unquote(Macro.escape(test_pid)), {:failing_release_kit_cmd, command, args, opts})
            {"boom", 17}
          end

          def mkdir_p(_path, _opts), do: :ok
          def write_file(_path, _content, _opts), do: :ok
        end,
        Macro.Env.location(__ENV__)
      )
    end

    artifact = %{
      name: :demo_app,
      cwd: "/srv/demo_app",
      manifest: "/srv/demo_app/_build/prod/artifacts/demo_app.etf",
      user: nil,
      mix_env: "prod",
      out_dir: "_build/prod/artifacts",
      timeout: 300_000
    }

    assert_raise ArgumentError, ~r/ReleaseKit artifact build failed for demo_app/, fn ->
      HostKit.Recipes.OTPRelease.build_release_kit_artifact!(artifact, runner: runner)
    end

    assert_receive {:failing_release_kit_cmd, "mix", ["release_kit.artifact" | _], _opts}
  end

  test "otp_release rejects non-OTP release manifests" do
    path =
      Path.join(System.tmp_dir!(), "hostkit-invalid-#{System.unique_integer([:positive])}.etf")

    File.write!(path, :erlang.term_to_binary(%{format: :other}))

    assert_raise ArgumentError, ~r/expected %ReleaseKit.Manifest{}/, fn ->
      HostKit.Recipes.OTPRelease.load_manifest!(path)
    end
  end

  defp write_manifest!(release_name, version) do
    path = Path.join(System.tmp_dir!(), "hostkit-otp-#{System.unique_integer([:positive])}.etf")

    File.write!(path, :erlang.term_to_binary(valid_manifest(release_name, version)))
    path
  end

  defp valid_manifest(release_name, version) do
    ReleaseKit.Manifest.new(
      app: release_name,
      version: version,
      release: release_name,
      mix_env: "prod",
      tarball: "/tmp/#{release_name}-#{version}.tar.gz",
      port: 4100,
      health_path: "/health",
      env_clear: %{"PHX_HOST" => "app.example.com"},
      env_secret: ["SECRET_KEY_BASE"]
    )
  end
end
