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

        account(system: true, home: Keyword.get(recipe_opts, :account_home, base_dir))

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
    release_kit = Keyword.get(opts, :release_kit)
    manifest_path = manifest_path(name, opts, release_kit)

    if collecting_release_kit?() and release_kit do
      collect_release_kit!(name, release_kit, manifest_path)
      placeholder_assigns(name, opts, manifest_path)
    else
      manifest = load_manifest!(manifest_path)
      assigns_from_manifest(name, opts, manifest_path, manifest)
    end
  end

  defp assigns_from_manifest(name, opts, manifest_path, manifest) do
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
        clear:
          manifest
          |> fetch_map!(:env)
          |> Map.get(:clear, %{})
          |> Map.merge(Keyword.get(opts, :env, %{}))
          |> stringify_env()
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

  def collect_release_kit(path, opts \\ []) do
    previous_collecting = Process.get(:hostkit_collect_release_kit?)
    previous_artifacts = Process.get(:hostkit_release_kit_artifacts)

    Process.put(:hostkit_collect_release_kit?, true)
    Process.put(:hostkit_release_kit_artifacts, [])

    previous_compiler_options = Code.compiler_options()
    files = collection_files(path, Keyword.get(opts, :require, []))
    modules_to_purge = modules_defined_in_files(files)
    loaded_before = loaded_modules()

    try do
      Code.compiler_options(ignore_module_conflict: true)
      Enum.each(Enum.drop(files, 1), &Code.require_file/1)
      Code.eval_file(hd(files))

      Process.get(:hostkit_release_kit_artifacts, [])
      |> Enum.reverse()
      |> filter_release_kit_artifacts(opts)
    after
      purge_eval_modules(modules_to_purge, loaded_before)
      Code.compiler_options(previous_compiler_options)
      restore_process(:hostkit_collect_release_kit?, previous_collecting)
      restore_process(:hostkit_release_kit_artifacts, previous_artifacts)
    end
  end

  def build_release_kit_artifacts!(artifacts, opts \\ []) do
    Enum.each(artifacts, &build_release_kit_artifact!(&1, opts))
  end

  defp filter_release_kit_artifacts(artifacts, opts) do
    case Keyword.get(opts, :services) do
      nil ->
        artifacts

      [] ->
        artifacts

      services ->
        selectors = services |> List.wrap() |> Enum.map(&to_string/1) |> MapSet.new()
        Enum.filter(artifacts, &MapSet.member?(selectors, to_string(&1.name)))
    end
  end

  def build_release_kit_artifact!(artifact, opts \\ []) do
    cwd = Map.fetch!(artifact, :cwd)
    mix_env = Map.fetch!(artifact, :mix_env)
    timeout = Map.fetch!(artifact, :timeout)

    args = release_kit_command(artifact)

    result =
      case artifact.user do
        nil ->
          HostKit.Runner.Ops.cmd(opts, "mix", args,
            cd: cwd,
            env: %{"MIX_ENV" => mix_env},
            timeout: timeout
          )

        user ->
          HostKit.Runner.Ops.cmd(
            Keyword.put(opts, :sudo, false),
            "sudo",
            ["-u", user, "-H", "env", "MIX_ENV=#{mix_env}", "mix" | args],
            cd: cwd,
            timeout: timeout
          )
      end

    case result do
      :ok ->
        :ok

      {:error, reason} ->
        raise ArgumentError, release_kit_failure_message(artifact, reason)
    end
  end

  def release_kit_label(%{name: name}), do: "release_kit.#{name}"

  def release_kit_command(%{out_dir: out_dir, skip_prebuild?: skip_prebuild?}) do
    args = ["release_kit.artifact", "--out-dir", out_dir]
    if skip_prebuild?, do: args ++ ["--skip-prebuild"], else: args
  end

  def release_kit_command_text(%{} = artifact) do
    command = ["mix" | release_kit_command(artifact)] |> Enum.join(" ")
    "MIX_ENV=#{artifact.mix_env} #{command}"
  end

  defp release_kit_failure_message(artifact, reason) do
    """
    ReleaseKit artifact build failed for #{artifact.name}
    cwd: #{artifact.cwd}
    user: #{artifact.user || "current"}
    command: #{release_kit_command_text(artifact)}
    reason: #{inspect(reason)}
    """
  end

  defp manifest_path(_name, opts, nil), do: Keyword.fetch!(opts, :manifest)

  defp manifest_path(name, opts, release_kit) when is_list(release_kit) do
    case Keyword.get(opts, :manifest) do
      nil ->
        cwd = Keyword.fetch!(release_kit, :cwd)
        out_dir = Keyword.get(release_kit, :out_dir, "_build/prod/artifacts")
        release = release_kit |> Keyword.get(:release, name) |> to_string()
        Path.expand(Path.join(out_dir, "#{release}.etf"), cwd)

      path ->
        path
    end
  end

  defp collecting_release_kit?, do: Process.get(:hostkit_collect_release_kit?, false)

  defp collect_release_kit!(name, release_kit, manifest_path) do
    artifact = %{
      name: name,
      cwd: Keyword.fetch!(release_kit, :cwd),
      manifest: manifest_path,
      user: Keyword.get(release_kit, :user),
      mix_env: release_kit |> Keyword.get(:mix_env, "prod") |> to_string(),
      out_dir: Keyword.get(release_kit, :out_dir, "_build/prod/artifacts"),
      timeout: Keyword.get(release_kit, :timeout, 300_000),
      skip_prebuild?: Keyword.get(release_kit, :skip_prebuild, false)
    }

    artifacts = Process.get(:hostkit_release_kit_artifacts, [])
    Process.put(:hostkit_release_kit_artifacts, [artifact | artifacts])
  end

  defp placeholder_assigns(name, opts, manifest_path) do
    app_name = Naming.identity_segment(name)
    port = Keyword.get(opts, :port, 4000)

    %{
      name: app_name,
      service_name: Keyword.get(opts, :service, name),
      manifest_path: manifest_path,
      version: "pending",
      tarball: "/tmp/#{app_name}-pending.tar.gz",
      timeout: Keyword.get(opts, :timeout, 300_000),
      env: %{clear: stringify_env(Keyword.get(opts, :env, %{}))},
      http: %{port: port},
      health: %{
        path: "/health",
        timeout: Keyword.get(opts, :health_timeout, 30),
        url: "http://127.0.0.1:#{port}/health"
      },
      release: %{name: to_string(name)},
      commands: %{
        unpack: Naming.resource([app_name, :unpack]),
        ready: Naming.resource([app_name, :ready])
      }
    }
  end

  defp loaded_modules do
    :code.all_loaded()
    |> Enum.map(fn {module, _path} -> module end)
    |> MapSet.new()
  end

  defp purge_eval_modules(modules, loaded_before) do
    modules
    |> Enum.reject(&MapSet.member?(loaded_before, &1))
    |> Enum.each(fn module ->
      :code.purge(module)
      :code.delete(module)
    end)
  end

  defp collection_files(path, files) do
    path = Path.expand(path)
    base = Path.dirname(path)

    [path | files |> List.wrap() |> Enum.map(&Path.expand(&1, base))]
  end

  defp modules_defined_in_files(files) do
    files
    |> Enum.flat_map(&modules_defined_in_file/1)
    |> Enum.uniq()
  end

  defp modules_defined_in_file(path) do
    path
    |> File.read!()
    |> Code.string_to_quoted!()
    |> then(fn ast ->
      {_ast, modules} =
        Macro.prewalk(ast, [], fn
          {:defmodule, _meta, [module_ast, _body]} = node, modules ->
            {node, collect_module(module_ast, modules)}

          node, modules ->
            {node, modules}
        end)

      modules
    end)
  rescue
    _ -> []
  end

  defp collect_module({:__aliases__, _meta, parts}, modules),
    do: [Module.concat(parts) | modules]

  defp collect_module(module, modules) when is_atom(module), do: [module | modules]
  defp collect_module(_module, modules), do: modules

  defp restore_process(key, nil), do: Process.delete(key)
  defp restore_process(key, value), do: Process.put(key, value)

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
    [
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
    |> Enum.each(&:erlang.atom_to_binary/1)
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
