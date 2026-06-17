defmodule HostKit.Recipes.OTPRelease do
  @moduledoc """
  Recipe for deploying an OTP release artifact with HostKit-managed resources.

  The recipe consumes a BEAM-native release artifact manifest (ETF) and expands
  it into ordinary HostKit resources. The application repository owns building
  the Mix release tarball; HostKit owns accounts, files, systemd, readiness, and
  rollback planning.
  """

  use HostKit.Recipe

  alias HostKit.Naming

  @format :beam_release_artifact
  @format_version 1

  defmacro otp_release(name, opts \\ []) do
    otp_release_body(name, opts, nil)
  end

  defmacro otp_release(name, opts, do: block) do
    otp_release_body(name, opts, block)
  end

  defp otp_release_body(name, opts, block) do
    quote do
      recipe_opts = unquote(opts)
      artifact = HostKit.Recipes.OTPRelease.assigns(unquote(name), recipe_opts)

      service artifact.service_name do
        base_dir = Keyword.get(recipe_opts, :base_dir, path(:opt, service_path()))
        config_dir = Keyword.get(recipe_opts, :config_dir, path(:config))
        release_dir = Path.join([base_dir, "releases", artifact.version])
        current_dir = Path.join(base_dir, "current")
        env_path = Keyword.get(recipe_opts, :env_path, Path.join(config_dir, "env"))
        release_bin = Path.join([release_dir, "bin", artifact.release.name])
        current_bin = Path.join([current_dir, "bin", artifact.release.name])
        unit = Keyword.get(recipe_opts, :unit, unit_name())

        account(system: true, home: base_dir)

        unquote(block)

        directory(base_dir, owner: service_user(), group: service_user(), mode: 0o755)

        directory(Path.join(base_dir, "releases"),
          owner: service_user(),
          group: service_user(),
          mode: 0o755
        )

        directory(config_dir, owner: "root", group: service_user(), mode: 0o750)

        dotenv env_path, owner: "root", group: service_user(), mode: 0o640 do
          for {key, value} <- artifact.env.clear do
            set(key, value)
          end
        end

        command(artifact.commands.unpack,
          exec: HostKit.Recipes.OTPRelease.unpack_exec(artifact.tarball, release_dir),
          creates: release_bin,
          timeout: artifact.timeout,
          down: :irreversible,
          meta: %{otp_release_artifact: artifact.manifest_path}
        )

        symlink(current_dir,
          to: release_dir,
          owner: service_user(),
          group: service_user(),
          depends_on: [{:command, artifact.commands.unpack}]
        )

        endpoint(:http,
          port: artifact.http.port,
          protocol: :http,
          health: artifact.health.path
        )

        daemon unit do
          description("#{artifact.name} OTP release")
          environment_file(env_path)
          working_directory(current_dir)
          exec_start([current_bin, "start"])
          service(kill_mode: :mixed, timeout_stop_sec: 10)
          restart(:on_failure)
          wanted_by(:multi_user)
        end

        ready artifact.commands.ready, timeout: artifact.health.timeout * 1000 do
          systemd(unit, restart: true, kill: true)
          http(artifact.health.url)
        end
      end
    end
  end

  def assigns(name, opts) when is_atom(name) do
    manifest_path = Keyword.fetch!(opts, :manifest)
    manifest = load_manifest!(manifest_path)
    release_name = fetch_string!(manifest, :release)
    version = fetch_string!(manifest, :version)
    app_name = Naming.identity_segment(name)
    port = Keyword.get(opts, :port, manifest |> fetch_map!(:health_check) |> Map.get(:port, 4000))
    health = health(fetch_map!(manifest, :health_check), port, opts)

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
      commands: %{
        unpack: Naming.resource([app_name, :unpack]),
        ready: Naming.resource([app_name, :ready])
      }
    }
  end

  def unpack_exec(tarball, release_dir) do
    script =
      bash("""
      rm -rf #{release_dir}
      mkdir -p #{release_dir}
      tar -xzf #{tarball} -C #{release_dir}
      """)

    {"bash", ["-euo", "pipefail", "-c", script.source]}
  end

  def load_manifest!(path) when is_binary(path) do
    preload_schema_atoms()

    path
    |> File.read!()
    |> :erlang.binary_to_term([:safe])
    |> validate_manifest!(path)
  end

  defp preload_schema_atoms do
    _schema_atoms = [
      :app,
      :clear,
      :command,
      :env,
      :format,
      :format_version,
      :health_check,
      :mix_env,
      :path,
      :port,
      :release,
      :runtime,
      :secret,
      :tarball,
      :tool,
      :url,
      :version,
      :beam_release_artifact
    ]

    :ok
  end

  defp validate_manifest!(%{} = manifest, path) do
    unless Map.get(manifest, :format) == @format do
      raise ArgumentError, "#{path} is not an OTP release artifact manifest"
    end

    unless Map.get(manifest, :format_version) == @format_version do
      raise ArgumentError, "unsupported OTP release artifact version in #{path}"
    end

    manifest
  end

  defp validate_manifest!(_manifest, path) do
    raise ArgumentError, "#{path} does not contain a valid OTP release artifact manifest"
  end

  defp health(raw, port, opts) do
    path = Map.get(raw, :path, "/health")

    %{
      path: path,
      timeout: Map.get(raw, :timeout, Keyword.get(opts, :health_timeout, 30)),
      url: Map.get(raw, :url, "http://127.0.0.1:#{port}#{path}")
    }
  end

  defp fetch_map!(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_map(value) -> value
      _other -> raise ArgumentError, "OTP release artifact missing map field #{inspect(key)}"
    end
  end

  defp fetch_string!(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) -> value
      _other -> raise ArgumentError, "OTP release artifact missing string field #{inspect(key)}"
    end
  end

  defp stringify_env(env) when is_map(env) do
    Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end
end
