defmodule HostKit.Recipes.XamalRelease do
  @moduledoc """
  Recipe for deploying a Xamal release artifact with HostKit-managed resources.

  The recipe consumes Xamal's BEAM-native HostKit artifact manifest (ETF) and
  expands it into ordinary HostKit resources. HostKit owns accounts, files,
  systemd, readiness, and rollback planning; Xamal owns release build metadata.
  """

  use HostKit.Recipe

  alias HostKit.Naming

  @format :xamal_hostkit_artifact
  @format_version 1

  defrecipe xamal_release(name, opts) do
    artifact = __MODULE__.assigns(name, opts)

    service artifact.service_name do
      account(system: true, home: artifact.paths.base)

      directory(artifact.paths.base, owner: service_user(), group: service_user(), mode: 0o755)

      directory(artifact.paths.releases,
        owner: service_user(),
        group: service_user(),
        mode: 0o755
      )

      directory(artifact.paths.config_dir, owner: "root", group: service_user(), mode: 0o750)

      dotenv artifact.paths.env, owner: "root", group: service_user(), mode: 0o640 do
        for {key, value} <- artifact.env.clear do
          set(key, value)
        end
      end

      command(artifact.commands.unpack,
        exec: HostKit.Recipes.XamalRelease.unpack_exec(artifact),
        creates: artifact.paths.release_bin,
        timeout: artifact.timeout,
        down: :irreversible,
        meta: %{xamal_artifact: artifact.manifest_path}
      )

      symlink(artifact.paths.current,
        to: artifact.paths.release_dir,
        owner: service_user(),
        group: service_user(),
        depends_on: [{:command, artifact.commands.unpack}]
      )

      endpoint(:http,
        port: artifact.http.port,
        protocol: :http,
        health: artifact.health.path
      )

      daemon artifact.unit do
        description("#{artifact.name} Xamal release")
        environment_file(artifact.paths.env)
        working_directory(artifact.paths.current)
        exec_start([artifact.paths.current_bin, "start"])
        service(kill_mode: :mixed, timeout_stop_sec: 10)
        restart(:on_failure)
        wanted_by(:multi_user)
      end

      ready artifact.commands.ready, timeout: artifact.health.timeout * 1000 do
        systemd(artifact.unit, restart: true, kill: true)
        http(artifact.health.url)
      end
    end
  end

  def assigns(name, opts) when is_atom(name) do
    manifest_path = Keyword.fetch!(opts, :manifest)
    manifest = load_manifest!(manifest_path)
    release = fetch_map!(manifest, :release)
    release_name = fetch_string!(release, :name)
    version = fetch_string!(manifest, :version)
    app_name = Naming.identity_segment(name)
    base_dir = Keyword.get(opts, :base_dir, "/opt/hostkit/xamal/#{app_name}")
    config_dir = Keyword.get(opts, :config_dir, "/etc/hostkit/xamal/#{app_name}")
    port = Keyword.get(opts, :port, 4000)
    health = health(fetch_map!(manifest, :health_check), port, opts)
    release_dir = Path.join([base_dir, "releases", version])
    current = Path.join(base_dir, "current")

    %{
      name: app_name,
      service_name: Keyword.get(opts, :service, name),
      manifest_path: manifest_path,
      version: version,
      tarball: fetch_string!(manifest, :tarball),
      timeout: Keyword.get(opts, :timeout, 300_000),
      env: %{
        clear: manifest |> fetch_map!(:env) |> Map.get(:clear, %{}) |> stringify_env()
      },
      http: %{port: port},
      health: health,
      release: %{name: release_name},
      unit: Keyword.get(opts, :unit, "#{app_name}.service"),
      paths: %{
        base: base_dir,
        releases: Path.join(base_dir, "releases"),
        release_dir: release_dir,
        current: current,
        config_dir: config_dir,
        env: Keyword.get(opts, :env_path, Path.join(config_dir, "env")),
        release_bin: Path.join([release_dir, "bin", release_name]),
        current_bin: Path.join([current, "bin", release_name])
      },
      commands: %{
        unpack: Naming.resource([app_name, :unpack]),
        ready: Naming.resource([app_name, :ready])
      }
    }
  end

  def unpack_exec(artifact) do
    tarball = HostKit.Shell.escape(artifact.tarball)
    release_dir = HostKit.Shell.escape(artifact.paths.release_dir)

    script =
      "rm -rf #{release_dir} && mkdir -p #{release_dir} && tar -xzf #{tarball} -C #{release_dir}"

    {"sh", ["-c", script]}
  end

  def load_manifest!(path) when is_binary(path) do
    path
    |> File.read!()
    |> :erlang.binary_to_term([:safe])
    |> validate_manifest!(path)
  end

  defp validate_manifest!(%{} = manifest, path) do
    unless Map.get(manifest, :format) == @format do
      raise ArgumentError, "#{path} is not a Xamal HostKit artifact manifest"
    end

    unless Map.get(manifest, :format_version) == @format_version do
      raise ArgumentError, "unsupported Xamal HostKit artifact version in #{path}"
    end

    manifest
  end

  defp validate_manifest!(_manifest, path) do
    raise ArgumentError, "#{path} does not contain a valid Xamal HostKit artifact manifest"
  end

  defp health(raw, port, opts) do
    path = Map.get(raw, :path, "/health")

    %{
      path: path,
      timeout: Map.get(raw, :timeout, Keyword.get(opts, :health_timeout, 30)),
      url: "http://127.0.0.1:#{port}#{path}"
    }
  end

  defp fetch_map!(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_map(value) -> value
      _other -> raise ArgumentError, "Xamal HostKit artifact missing map field #{inspect(key)}"
    end
  end

  defp fetch_string!(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) -> value
      _other -> raise ArgumentError, "Xamal HostKit artifact missing string field #{inspect(key)}"
    end
  end

  defp stringify_env(env) when is_map(env) do
    Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end
end
