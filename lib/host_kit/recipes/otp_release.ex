defmodule HostKit.Recipes.OTPRelease do
  @moduledoc """
  Recipe for deploying an OTP release artifact with HostKit-managed resources.

  The recipe consumes a BEAM-native release artifact manifest (ETF) and expands
  it into ordinary HostKit resources. The application repository owns building
  the Mix release tarball; HostKit owns accounts, files, systemd, readiness, and
  rollback planning.
  """

  use HostKit.Recipe
  use DSL.Macros

  alias HostKit.Naming
  alias HostKit.Recipes.OTPRelease.Scope

  @format :beam_release_artifact
  @format_version 2

  defaround otp_release(name), optional: true do
    otp_release name, [] do
      yield()
    end
  end

  defaround otp_release(name, opts), optional: true do
    recipe_opts = opts
    artifact = HostKit.Recipes.OTPRelease.assigns(name, recipe_opts)

    service_opts = HostKit.Recipes.OTPRelease.service_opts(name, recipe_opts)

    service artifact.service_name, service_opts do
      base_dir = Keyword.get(recipe_opts, :base_dir, path(:opt, service_path()))
      config_dir = Keyword.get(recipe_opts, :config_dir, path(:config))
      release_dir = Path.join([base_dir, "releases", artifact.version])
      current_dir = Path.join(base_dir, "current")
      env_path = Keyword.get(recipe_opts, :env_path, Path.join(config_dir, "env"))
      release_bin = Path.join([release_dir, "bin", artifact.release.name])
      current_bin = Path.join([current_dir, "bin", artifact.release.name])
      unit = Keyword.get(recipe_opts, :unit, unit_name())

      account(system: true, home: Keyword.get(recipe_opts, :account_home, base_dir))

      lifecycle_context =
        HostKit.DSL.Lifecycle.Scope.start_context(%{
          collect?: true,
          name: &HostKit.Recipes.OTPRelease.lifecycle_command_name(artifact.name, &1),
          eval: &HostKit.Recipes.OTPRelease.release_eval_exec(current_bin, env_path, &1, &2),
          user: service_user(),
          env_files: [env_path],
          timeout: artifact.timeout,
          down: :irreversible,
          inputs: [release_dir],
          depends_on: [
            {:command, artifact.commands.unpack},
            {:symlink, current_dir}
          ]
        })

      yield()

      lifecycle_commands = HostKit.DSL.Lifecycle.Scope.finish_context(lifecycle_context)

      lifecycle_commands =
        HostKit.Recipes.OTPRelease.with_stop_dependency(
          lifecycle_commands,
          artifact.commands.stop
        )

      package(:tar, as: "tar")

      directory(base_dir, owner: service_user(), group: service_user(), mode: 0o755)

      directory(Path.join(base_dir, "releases"),
        owner: service_user(),
        group: service_user(),
        mode: 0o755
      )

      directory(config_dir, owner: "root", group: service_user(), mode: 0o750)

      HostKit.DSL.Scope.put_release_metadata(artifact.name, %{
        name: artifact.name,
        kind: :otp_release,
        version: artifact.version,
        releases_dir: Path.join(base_dir, "releases"),
        release_path: release_dir,
        current_path: current_dir,
        artifact_dir: Path.dirname(artifact.manifest_path),
        artifact_prefix:
          HostKit.Recipes.OTPRelease.artifact_prefix(
            artifact.tarball,
            artifact.release.name,
            artifact.version
          ),
        keep: Keyword.get(recipe_opts, :keep)
      })

      dotenv env_path, owner: "root", group: service_user(), mode: 0o640 do
        for {key, value} <- artifact.env.clear do
          set(key, value)
        end

        for key <- artifact.env.secret do
          secret(key, env: :redacted)
        end
      end

      command(HostKit.Recipes.OTPRelease.unpack_clean_command(artifact),
        exec: {"rm", ["-rf", release_dir]},
        creates: release_bin,
        timeout: artifact.timeout,
        down: :irreversible,
        meta: %{otp_release_artifact: artifact.manifest_path}
      )

      command(HostKit.Recipes.OTPRelease.unpack_mkdir_command(artifact),
        exec: {"mkdir", ["-p", release_dir]},
        creates: release_dir,
        timeout: artifact.timeout,
        down: :irreversible,
        depends_on: [{:command, HostKit.Recipes.OTPRelease.unpack_clean_command(artifact)}],
        meta: %{otp_release_artifact: artifact.manifest_path}
      )

      command(artifact.commands.unpack,
        exec: {"tar", ["-xzf", artifact.tarball, "-C", release_dir]},
        creates: release_bin,
        timeout: artifact.timeout,
        down: :irreversible,
        depends_on: [{:command, HostKit.Recipes.OTPRelease.unpack_mkdir_command(artifact)}],
        meta: %{otp_release_artifact: artifact.manifest_path}
      )

      symlink(current_dir,
        to: release_dir,
        depends_on: [{:command, artifact.commands.unpack}]
      )

      if lifecycle_commands != [] do
        command(artifact.commands.stop,
          exec: {"systemctl", ["stop", unit]},
          success_codes: [0, 5],
          timeout: artifact.timeout,
          down: :irreversible,
          inputs: [release_dir],
          depends_on: [
            {:command, artifact.commands.unpack},
            {:symlink, current_dir}
          ],
          meta: %{otp_release_artifact: artifact.manifest_path}
        )
      end

      for lifecycle_command <- lifecycle_commands do
        HostKit.DSL.Scope.add_resource(lifecycle_command)
      end

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

      ready artifact.commands.ready,
        timeout: artifact.health.timeout * 1000,
        depends_on: Enum.map(lifecycle_commands, &HostKit.Resource.id/1) do
        systemd(unit, restart: true, kill: true)
        http(artifact.health.url)
      end
    end
  end

  def service_opts(release_name, recipe_opts)
      when is_atom(release_name) and is_list(recipe_opts) do
    base_opts =
      case Keyword.get(recipe_opts, :path) do
        nil -> []
        path -> [path: path]
      end

    meta =
      recipe_opts
      |> Keyword.get(:meta, %{})
      |> Map.update(:aliases, [release_name], fn aliases ->
        aliases |> List.wrap() |> Kernel.++([release_name]) |> Enum.uniq()
      end)

    Keyword.put(base_opts, :meta, meta)
  end

  def assigns(name, opts) when is_atom(name) do
    release_kit = Keyword.get(opts, :release_kit)
    manifest_path = manifest_path(name, opts, release_kit)

    if Scope.collecting_release_kit?() and release_kit do
      collect_release_kit!(name, opts, release_kit, manifest_path)
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
          |> stringify_env(),
        secret:
          manifest
          |> fetch_map!(:env)
          |> Map.get(:secret, [])
          |> Enum.map(&to_string/1)
      },
      http: %{port: port},
      health: health,
      release: %{name: release_name},
      commands: %{
        unpack: Naming.resource([app_name, :unpack]),
        stop: Naming.resource([app_name, :stop_for_lifecycle]),
        ready: Naming.resource([app_name, :ready])
      }
    }
  end

  def collect_release_kit(path, opts \\ []) do
    path
    |> collect_release_kit_context(opts)
    |> Map.fetch!(:artifacts)
  end

  def collect_release_kit_context(path, opts \\ []) do
    previous_collection = Scope.start_release_kit_collection()

    previous_compiler_options = Code.compiler_options()
    files = collection_files(path, Keyword.get(opts, :require, []))
    modules_to_purge = modules_defined_in_files(files)
    loaded_before = loaded_modules()

    try do
      Code.compiler_options(ignore_module_conflict: true)
      Enum.each(Enum.drop(files, 1), &Code.require_file/1)
      {project, _binding} = Code.eval_file(hd(files))

      artifacts =
        Scope.release_kit_artifacts_collected()
        |> Enum.reverse()
        |> filter_release_kit_artifacts(opts)

      %{project: project, artifacts: artifacts}
    after
      purge_eval_modules(modules_to_purge, loaded_before)
      Code.compiler_options(previous_compiler_options)
      Scope.restore_release_kit_collection(previous_collection)
    end
  end

  def prepare_project(%HostKit.Project{} = project, artifacts, opts \\ []) do
    project = %{project | meta: Map.delete(project.meta, :firewall)}
    resources = HostKit.Project.resources(project, services: Keyword.get(opts, :services))

    prepare_resources =
      resources
      |> Enum.filter(&prepare_dependency?/1)
      |> Kernel.++(Enum.flat_map(artifacts, &prepare_commands(&1, resources)))

    %{
      project
      | services: [],
        instances: [],
        proxies: [],
        resources: prepare_resources,
        meta: Map.delete(project.meta, :firewall)
    }
  end

  def build_release_kit_artifacts!(artifacts, opts \\ []) do
    Enum.each(artifacts, &build_release_kit_artifact!(&1, opts))
  end

  defp prepare_dependency?(%HostKit.Resources.Source{}), do: true
  defp prepare_dependency?(%HostKit.Resources.Package{}), do: true
  defp prepare_dependency?(%HostKit.Resources.Capability{}), do: true
  defp prepare_dependency?(%HostKit.Resources.Mise{}), do: true
  defp prepare_dependency?(_resource), do: false

  defp prepare_commands(artifact, resources) do
    source_inputs = release_kit_source_inputs(artifact, resources)
    deps = release_kit_deps_command(artifact, source_inputs)
    artifact_command = release_kit_artifact_command(artifact, source_inputs, deps)

    [deps, artifact_command]
  end

  defp release_kit_deps_command(artifact, source_inputs) do
    HostKit.Resources.Command.new(release_kit_command_name(artifact, :deps),
      exec: release_kit_exec(artifact, ["deps.get", "--only", artifact.mix_env]),
      cwd: artifact.cwd,
      user: artifact.user,
      env: release_kit_env(artifact),
      inputs:
        source_inputs ++ release_kit_existing_path_inputs(artifact, ["mix.exs", "mix.lock"]),
      outputs: ["deps"],
      stamp: release_kit_command_stamp(artifact, :deps),
      timeout: artifact.timeout,
      meta: release_kit_command_meta(artifact)
    )
  end

  defp release_kit_artifact_command(artifact, source_inputs, deps) do
    HostKit.Resources.Command.new(release_kit_command_name(artifact, :artifact),
      exec: release_kit_exec(artifact, release_kit_command(artifact)),
      cwd: artifact.cwd,
      user: artifact.user,
      env: release_kit_env(artifact),
      inputs: source_inputs ++ release_kit_path_inputs(artifact),
      outputs: [release_kit_manifest_output(artifact)],
      stamp: release_kit_command_stamp(artifact, :artifact),
      timeout: artifact.timeout,
      depends_on: [HostKit.Resource.id(deps)],
      meta: release_kit_command_meta(artifact)
    )
  end

  defp release_kit_command_name(%{name: name}, step),
    do: Naming.resource([name, :release_kit, step])

  defp release_kit_command_stamp(%{cwd: cwd} = artifact, step) do
    Path.join([cwd, "_build/hostkit", "#{release_kit_command_name(artifact, step)}.json"])
  end

  defp release_kit_source_inputs(%{cwd: cwd}, resources) do
    cwd = Path.expand(cwd)

    resources
    |> Enum.filter(&match?(%HostKit.Resources.Source{}, &1))
    |> Enum.filter(fn source -> release_kit_cwd_inside_source?(cwd, source) end)
    |> Enum.map(& &1.name)
  end

  defp release_kit_cwd_inside_source?(cwd, source) do
    app_path = source |> HostKit.Resources.Source.app_path() |> Path.expand()
    checkout = Path.expand(source.checkout)

    cwd == app_path or cwd == checkout or String.starts_with?(cwd <> "/", app_path <> "/")
  end

  defp release_kit_path_inputs(artifact) do
    release_kit_existing_path_inputs(artifact, ["mix.exs", "mix.lock", "config", "lib", "assets"])
  end

  defp release_kit_existing_path_inputs(%{cwd: cwd}, paths) do
    Enum.filter(paths, &File.exists?(Path.join(cwd, &1)))
  end

  defp release_kit_manifest_output(%{cwd: cwd, manifest: manifest}) do
    manifest
    |> Path.expand()
    |> Path.relative_to(Path.expand(cwd))
  end

  defp release_kit_exec(_artifact, args), do: {System.find_executable("mix") || "mix", args}

  defp release_kit_env(%{mix_env: mix_env}), do: %{"MIX_ENV" => mix_env}

  defp release_kit_command_meta(%{manifest: manifest}) do
    %{release_kit_artifact: manifest}
  end

  defp filter_release_kit_artifacts(artifacts, opts) do
    case Keyword.get(opts, :services) do
      nil ->
        artifacts

      [] ->
        artifacts

      services ->
        selectors = services |> List.wrap() |> Enum.map(&to_string/1) |> MapSet.new()

        Enum.filter(artifacts, fn artifact ->
          MapSet.member?(selectors, to_string(artifact.name)) or
            MapSet.member?(selectors, to_string(artifact.service_name))
        end)
    end
  end

  def with_stop_dependency([], _stop_command), do: []

  def with_stop_dependency(commands, stop_command) do
    Enum.map(commands, fn command ->
      depends_on = [{:command, stop_command} | command.depends_on]
      %{command | depends_on: Enum.uniq(depends_on)}
    end)
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

  def lifecycle_command_name(app_name, step), do: Naming.resource([app_name, step])

  def release_eval_exec(release_bin, _env_path, expression, _opts \\ []) do
    {release_bin, ["eval", expression]}
  end

  def release_kit_command(%{out_dir: out_dir}) do
    ["release_kit.artifact", "--out-dir", out_dir]
  end

  def artifact_prefix(tarball, release_name, version)
      when is_binary(tarball) and is_binary(release_name) and is_binary(version) do
    basename = Path.basename(tarball)
    suffix = "-#{version}.tar.gz"

    if String.ends_with?(basename, suffix) do
      String.replace_suffix(basename, suffix, "")
    else
      release_name
    end
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

  defp collect_release_kit!(name, opts, release_kit, manifest_path) do
    artifact = %{
      name: name,
      service_name: Keyword.get(opts, :service, name),
      cwd: Keyword.fetch!(release_kit, :cwd),
      manifest: manifest_path,
      user: Keyword.get(release_kit, :user),
      mix_env: release_kit |> Keyword.get(:mix_env, "prod") |> to_string(),
      out_dir: Keyword.get(release_kit, :out_dir, "_build/prod/artifacts"),
      timeout: Keyword.get(release_kit, :timeout, 300_000)
    }

    Scope.collect_release_kit_artifact(artifact)
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
      env: %{clear: stringify_env(Keyword.get(opts, :env, %{})), secret: []},
      http: %{port: port},
      health: %{
        path: "/health",
        timeout: Keyword.get(opts, :health_timeout, 30),
        url: "http://127.0.0.1:#{port}/health"
      },
      release: %{name: to_string(name)},
      commands: %{
        unpack: Naming.resource([app_name, :unpack]),
        stop: Naming.resource([app_name, :stop_for_lifecycle]),
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
    _exception in [File.Error, SyntaxError, TokenMissingError, ArgumentError] -> []
  end

  defp collect_module({:__aliases__, _meta, parts}, modules),
    do: [Module.concat(parts) | modules]

  defp collect_module(module, modules) when is_atom(module), do: [module | modules]
  defp collect_module(_module, modules), do: modules

  def unpack_clean_command(%{name: name}), do: Naming.resource([name, :unpack, :clean])
  def unpack_mkdir_command(%{name: name}), do: Naming.resource([name, :unpack, :mkdir])

  def load_manifest!(path) when is_binary(path) do
    unless Code.ensure_loaded?(ReleaseKit.Manifest) do
      raise ArgumentError,
            "ReleaseKit OTP artifact manifests require adding {:release_kit, \"~> 0.2.1\"}"
    end

    ReleaseKit.Manifest
    |> apply(:read!, [path])
    |> validate_manifest!(path)
  end

  defp validate_manifest!(%{__struct__: module} = manifest, path)
       when module == ReleaseKit.Manifest do
    unless manifest.format == @format do
      raise ArgumentError, "#{path} is not an OTP release artifact manifest"
    end

    unless manifest.format_version == @format_version do
      raise ArgumentError, "unsupported OTP release artifact version in #{path}"
    end

    manifest
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
