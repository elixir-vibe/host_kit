defmodule HostKit.XamalReleaseRecipeTest do
  use HostKit.Case, async: true

  test "xamal_release recipe expands artifact manifest to ordinary resources" do
    manifest_path = write_manifest!("demo_app", "abc123")

    defmodule XamalReleaseRecipeProject do
      use HostKit.DSL, recipes: [HostKit.Recipes.XamalRelease]

      def project(manifest_path) do
        project :demo do
          xamal_release(:demo_app,
            manifest: manifest_path,
            port: 4100,
            base_dir: "/opt/example/demo_app",
            config_dir: "/etc/example/demo_app"
          )
        end
      end
    end

    project = XamalReleaseRecipeProject.project(manifest_path)
    resources = HostKit.Project.resources(project)
    assert [service] = project.services

    assert %HostKit.Endpoint{port: 4100, protocol: :http, health: "/health"} =
             service.meta.endpoints.http

    assert Enum.any?(resources, &match?(%HostKit.Resources.Account{name: "demo-app"}, &1))

    assert Enum.any?(resources, fn
             %HostKit.Resources.EnvFile{path: "/etc/example/demo_app/env", entries: entries} ->
               {:set, "PHX_HOST", "app.example.com"} in entries

             _resource ->
               false
           end)

    assert Enum.any?(resources, fn
             %HostKit.Resources.Command{
               name: "demo_app_unpack",
               exec: {"sh", ["-c", command]},
               creates: "/opt/example/demo_app/releases/abc123/bin/demo_app",
               down: :irreversible
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

  test "xamal_release rejects non-Xamal manifests" do
    path =
      Path.join(System.tmp_dir!(), "hostkit-invalid-#{System.unique_integer([:positive])}.etf")

    File.write!(path, :erlang.term_to_binary(%{format: :other}))

    assert_raise ArgumentError, ~r/not a Xamal HostKit artifact/, fn ->
      HostKit.Recipes.XamalRelease.load_manifest!(path)
    end
  end

  defp write_manifest!(release_name, version) do
    path = Path.join(System.tmp_dir!(), "hostkit-xamal-#{System.unique_integer([:positive])}.etf")

    manifest = %{
      tool: :xamal,
      format: :xamal_hostkit_artifact,
      format_version: 1,
      service: release_name,
      version: version,
      release: %{name: release_name, mix_env: "prod"},
      tarball: "/tmp/#{release_name}-#{version}.tar.gz",
      hostkit: %{project: "example", service: release_name},
      env: %{clear: %{"PHX_HOST" => "app.example.com"}, secret: ["SECRET_KEY_BASE"]},
      health_check: %{path: "/health", interval: 1, timeout: 30}
    }

    File.write!(path, :erlang.term_to_binary(manifest))
    path
  end
end
