defmodule HostKit.CleanTest do
  use HostKit.Case, async: true

  defmodule CleanOTPReleaseProject do
    use HostKit.DSL, recipes: [HostKit.Recipes.OTPRelease]

    def build_project(manifest_path, base) do
      project :demo do
        roots(opt: "/opt/apps", config: "/etc/apps")

        otp_release(:llm_proxy,
          manifest: manifest_path,
          base_dir: base,
          config_dir: Path.join(base, "config")
        )
      end
    end
  end

  test "plans conservative OTP release cleanup from existing release metadata" do
    root = tmp_dir("hostkit-clean")
    app = Path.join(root, "app")
    base = Path.join(root, "releases/llm-proxy")
    releases = Path.join(base, "releases")
    artifacts = Path.join(app, "_build/prod/artifacts")

    File.mkdir_p!(releases)
    File.mkdir_p!(artifacts)

    for {version, index} <-
          Enum.with_index(["20260626-a05f74e", "20260628-71a3975", "20260629-deadbee"]) do
      release_path = Path.join(releases, version)
      File.mkdir_p!(release_path)
      File.touch!(release_path, 1_700_000_000 + index)
      File.write!(Path.join(artifacts, "llm_proxy-#{version}.tar.gz"), version)
      File.write!(Path.join(artifacts, "llm_proxy-#{version}.tar.gz.sha256"), version)
    end

    File.write!(Path.join(artifacts, "llm_proxy-20260627-orphaned.tar.gz"), "orphaned")
    File.write!(Path.join(artifacts, "llm_proxy-20260627-orphaned.tar.gz.sha256"), "orphaned")

    File.ln_s!(Path.join(releases, "20260629-deadbee"), Path.join(base, "current"))

    manifest_path = write_manifest(artifacts, "20260629-deadbee")
    project = project_with_otp_release(manifest_path, base)

    assert {:ok, plan} = HostKit.clean(project, keep: 2)

    paths =
      Enum.map(plan.changes, & &1.after.exec) |> Enum.map(fn {"rm", ["-rf", path]} -> path end)

    assert Path.join(releases, "20260626-a05f74e") in paths
    assert Path.join(artifacts, "llm_proxy-20260626-a05f74e.tar.gz") in paths
    assert Path.join(artifacts, "llm_proxy-20260626-a05f74e.tar.gz.sha256") in paths
    assert Path.join(artifacts, "llm_proxy-20260627-orphaned.tar.gz") in paths
    assert Path.join(artifacts, "llm_proxy-20260627-orphaned.tar.gz.sha256") in paths

    refute Path.join(releases, "20260628-71a3975") in paths
    refute Path.join(releases, "20260629-deadbee") in paths
    refute manifest_path in paths
  after
    cleanup_tmp("hostkit-clean")
  end

  test "orders same-date hash releases by directory modification time" do
    root = tmp_dir("hostkit-clean-mtime")
    base = Path.join(root, "releases/llm-proxy")
    releases = Path.join(base, "releases")
    artifacts = Path.join(root, "artifacts")
    File.mkdir_p!(releases)
    File.mkdir_p!(artifacts)

    versions = [
      {"20260726-fffffff", 1_700_000_000},
      {"20260726-0000001", 1_700_000_100},
      {"20260726-8888888", 1_700_000_200}
    ]

    for {version, modified_at} <- versions do
      release_path = Path.join(releases, version)
      File.mkdir_p!(release_path)
      File.touch!(release_path, modified_at)
      File.write!(Path.join(artifacts, "llm_proxy-#{version}.tar.gz"), version)
    end

    File.ln_s!(Path.join(releases, "20260726-8888888"), Path.join(base, "current"))
    manifest_path = write_manifest(artifacts, "20260726-8888888")
    project = project_with_otp_release(manifest_path, base)

    assert {:ok, plan} = HostKit.clean(project, keep: 2)
    paths = cleanup_paths(plan)

    assert Path.join(releases, "20260726-fffffff") in paths
    refute Path.join(releases, "20260726-0000001") in paths
    refute Path.join(releases, "20260726-8888888") in paths
  after
    cleanup_tmp("hostkit-clean-mtime")
  end

  test "protects an explicit known-good rollback across failed newer releases" do
    root = tmp_dir("hostkit-clean-protected")
    base = Path.join(root, "releases/llm-proxy")
    releases = Path.join(base, "releases")
    artifacts = Path.join(root, "artifacts")
    File.mkdir_p!(releases)
    File.mkdir_p!(artifacts)

    versions = [
      {"20260726-b603078", 1_700_000_000},
      {"20260726-bf069e1", 1_700_000_100},
      {"20260726-e64a98b", 1_700_000_200}
    ]

    for {version, modified_at} <- versions do
      release_path = Path.join(releases, version)
      File.mkdir_p!(release_path)
      File.touch!(release_path, modified_at)
      File.write!(Path.join(artifacts, "llm_proxy-#{version}.tar.gz"), version)
      File.write!(Path.join(artifacts, "llm_proxy-#{version}.tar.gz.sha256"), version)
    end

    File.ln_s!(Path.join(releases, "20260726-e64a98b"), Path.join(base, "current"))
    manifest_path = write_manifest(artifacts, "20260726-e64a98b")
    project = project_with_otp_release(manifest_path, base)

    assert {:ok, plan} =
             HostKit.clean(project,
               keep: 1,
               protect_versions: ["20260726-b603078"]
             )

    paths = cleanup_paths(plan)

    assert Path.join(releases, "20260726-bf069e1") in paths
    assert Path.join(artifacts, "llm_proxy-20260726-bf069e1.tar.gz") in paths
    refute Path.join(releases, "20260726-b603078") in paths
    refute Path.join(artifacts, "llm_proxy-20260726-b603078.tar.gz") in paths
    refute Path.join(releases, "20260726-e64a98b") in paths
  after
    cleanup_tmp("hostkit-clean-protected")
  end

  test "release DSL records release metadata on the existing service" do
    project =
      Code.eval_string("""
      use HostKit.DSL

      project :demo do
        roots opt: "/opt/apps"

        service :gatus do
          release :gatus, version: "5.36.0"
        end
      end
      """)
      |> elem(0)

    assert [%HostKit.Service{meta: %{releases: %{"gatus" => release}}}] = project.services
    assert release.kind == :release
    assert release.releases_dir == "/opt/apps/releases/gatus"
    assert release.current_path == "/opt/apps/current/gatus"
  end

  defp cleanup_paths(plan) do
    Enum.map(plan.changes, fn change ->
      {"rm", ["-rf", path]} = change.after.exec
      path
    end)
  end

  defp write_manifest(artifacts, version) do
    manifest_path = Path.join(artifacts, "llm_proxy.etf")

    manifest =
      ReleaseKit.Manifest.new(
        app: "llm_proxy",
        version: version,
        release: "llm_proxy",
        mix_env: "prod",
        tarball: Path.join(artifacts, "llm_proxy-#{version}.tar.gz"),
        port: 4101,
        health_path: "/health"
      )

    File.write!(manifest_path, :erlang.term_to_binary(manifest))
    manifest_path
  end

  defp project_with_otp_release(manifest_path, base),
    do: CleanOTPReleaseProject.build_project(manifest_path, base)

  defp tmp_dir(name) do
    path = Path.join(System.tmp_dir!(), name)
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp cleanup_tmp(name) do
    HostKit.SafeTmp.rm_rf!(Path.join(System.tmp_dir!(), name), "hostkit-")
  end
end
