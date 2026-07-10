defmodule HostKit.Recipes.Gatehouse do
  @moduledoc "Recipe for running an already-built Gatehouse release under systemd."

  use HostKit.Recipe

  alias HostKit.Naming

  defrecipe gatehouse_release(name, opts) do
    release = __MODULE__.release_assigns(name, opts)

    service release.service_name do
      package(:build_essential, as: "build-essential")
      package(:cmake, as: "cmake")

      mise name: release.runtime.name, packages: release.runtime.mise_packages do
        tool(:erlang, release.runtime.erlang)
        tool(:elixir, release.runtime.elixir)
      end

      directory(Path.dirname(release.paths.install), owner: "root", group: "root", mode: 0o755)
      directory(release.paths.base, owner: "root", group: "root", mode: 0o755)

      source(release.source.name,
        git: release.source.repo,
        ref: release.source.ref,
        checkout: release.paths.source,
        path: release.source.path,
        dirty: :reset
      )

      command(release.commands.deps.name,
        exec: ["mix", "deps.get", "--only", "prod"],
        runtime: {:mise, release.runtime.name},
        cwd: release.paths.app_dir,
        env: %{"MIX_ENV" => "prod"},
        inputs: [release.source.name, "mix.exs", "mix.lock"],
        outputs: ["deps"],
        timeout: 300_000
      )

      command(release.commands.release.name,
        exec: ["mix", "release"],
        runtime: {:mise, release.runtime.name},
        cwd: release.paths.app_dir,
        env: %{"MIX_ENV" => "prod"},
        creates: release.paths.release_bin,
        inputs: [release.source.name, "mix.exs", "mix.lock", "lib", "config"],
        outputs: [release.paths.release_bin],
        timeout: 300_000
      )

      command(release.commands.install.name,
        exec: [
          "sh",
          "-c",
          "set -eu; rm -rf \"$1\"; mkdir -p \"$(dirname \"$1\")\"; cp -a \"$2\" \"$1\"",
          "hostkit-gatehouse-install",
          release.paths.install,
          release.paths.built_release
        ],
        creates: release.paths.install_bin,
        inputs: [release.paths.release_bin],
        outputs: [release.paths.install_bin],
        timeout: 300_000
      )
    end
  end

  defrecipe gatehouse(name, opts) do
    gatehouse = __MODULE__.assigns(name, opts)

    service gatehouse.service_name do
      directory(gatehouse.paths.config_dir, owner: "root", group: "root", mode: 0o755)

      directory(gatehouse.paths.state_dir,
        owner: gatehouse.owner,
        group: gatehouse.group,
        mode: 0o755
      )

      if gatehouse.paths.env_dir != gatehouse.paths.config_dir do
        directory(gatehouse.paths.env_dir, owner: "root", group: "root", mode: 0o755)
      end

      dotenv gatehouse.paths.env, owner: "root", group: "root", mode: 0o600 do
        set("GATEHOUSE_CONFIG", gatehouse.paths.config)
        set("GATEHOUSE_STATE", gatehouse.paths.state)
        set("RELEASE_DISTRIBUTION", "name")

        if gatehouse.cookie do
          set("GATEHOUSE_COOKIE", gatehouse.cookie)
        end
      end

      daemon gatehouse.paths.service_unit do
        description("Gatehouse edge proxy #{gatehouse.name}")
        environment_file(gatehouse.paths.env)
        working_directory(gatehouse.paths.release)
        exec_start([gatehouse.paths.bin, "start"])
        exec_stop([gatehouse.paths.bin, "stop"])
        service_user(gatehouse.owner)
        service_group(gatehouse.group)
        service(kill_mode: :mixed, timeout_stop_sec: 15)
        restart(:on_failure)
        wanted_by(:multi_user)
      end

      ready gatehouse.ready_name, timeout: gatehouse.readiness.timeout do
        systemd(gatehouse.paths.service_unit,
          restart: gatehouse.readiness.restart,
          kill: gatehouse.readiness.kill
        )
      end
    end
  end

  def release_assigns(name, opts) when is_atom(name) or is_binary(name) do
    gatehouse_name = Naming.identity_segment(name)
    source = Keyword.fetch!(opts, :source)
    runtime = Keyword.get(opts, :runtime, [])
    release_path = Keyword.get(opts, :release_path, "/opt/gatehouse")

    release = %{
      name: gatehouse_name,
      service_name: Keyword.get(opts, :service, :gatehouse_release),
      source: Map.put(normalize_source(source), :name, name),
      runtime: %{
        name: Keyword.get(runtime, :name, :gatehouse_beam),
        erlang: Keyword.get(runtime, :erlang, "29.0.2"),
        elixir: Keyword.get(runtime, :elixir, "1.20.1"),
        mise_packages: Keyword.get(runtime, :mise_packages, beam_packages())
      },
      install: release_path
    }

    paths = release_paths(release)

    release
    |> Map.put(:paths, paths)
    |> Map.put(:commands, release_commands(release, paths))
  end

  def assigns(name, opts) when is_atom(name) or is_binary(name) do
    gatehouse_name = Naming.identity_segment(name)
    release_path = Keyword.get(opts, :release_path, "/opt/gatehouse")
    config_path = Keyword.get(opts, :config_path, "/etc/gatehouse/config.exs")
    state_path = Keyword.get(opts, :state_path, "/var/lib/gatehouse/state.etf")
    env_path = Keyword.get(opts, :env_path, "/etc/gatehouse/env")
    service_unit = Keyword.get(opts, :service_unit, "gatehouse.service")

    %{
      name: gatehouse_name,
      service_name: Keyword.get(opts, :service, :gatehouse),
      owner: HostKit.Account.name!(Keyword.get(opts, :run_as, "gatehouse")),
      group:
        HostKit.Account.name!(Keyword.get(opts, :group, Keyword.get(opts, :run_as, "gatehouse"))),
      cookie: Keyword.get(opts, :cookie),
      ready_name: Naming.readiness(:gatehouse, gatehouse_name),
      paths: %{
        release: release_path,
        bin: Path.join([release_path, "bin", "gatehouse"]),
        config: config_path,
        config_dir: Path.dirname(config_path),
        state: state_path,
        state_dir: Path.dirname(state_path),
        env: env_path,
        env_dir: Path.dirname(env_path),
        service_unit: service_unit
      },
      readiness: %{
        timeout: Keyword.get(opts, :readiness_timeout, 30_000),
        restart: Keyword.get(opts, :restart, true),
        kill: Keyword.get(opts, :kill, true)
      }
    }
  end

  defp normalize_source(source) do
    %{
      repo: repo_url(source),
      ref: Keyword.get(source, :ref, "main"),
      path: Keyword.get(source, :path, ".")
    }
  end

  defp repo_url(source) do
    cond do
      url = Keyword.get(source, :url) -> url
      git = Keyword.get(source, :git) -> git
      github = Keyword.get(source, :github) -> "https://github.com/#{github}.git"
      true -> raise ArgumentError, "gatehouse_release source expects :url, :git, or :github"
    end
  end

  defp release_paths(release) do
    base = "/opt/hostkit/build/gatehouse/#{release.name}"
    source = Path.join(base, "source")
    app_dir = Path.expand(release.source.path, source)
    built_release = Path.join([app_dir, "_build/prod/rel/gatehouse"])

    %{
      base: base,
      source: source,
      app_dir: app_dir,
      built_release: built_release,
      release_bin: Path.join([built_release, "bin", "gatehouse"]),
      install: release.install,
      install_bin: Path.join([release.install, "bin", "gatehouse"])
    }
  end

  defp release_commands(release, _paths) do
    %{
      deps: %{name: Naming.resource([:gatehouse, release.name, :deps])},
      release: %{name: Naming.resource([:gatehouse, release.name, :release])},
      install: %{name: Naming.resource([:gatehouse, release.name, :install])}
    }
  end

  defp beam_packages do
    [
      :curl,
      :ca_certificates,
      :git,
      :autoconf,
      :make,
      :gcc,
      :perl,
      :m4,
      :openssl_dev,
      :ncurses_dev,
      :unzip,
      :xsltproc
    ]
  end
end
