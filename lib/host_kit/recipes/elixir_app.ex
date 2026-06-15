defmodule HostKit.Recipes.ElixirApp do
  @moduledoc "Recipe for building and running a Phoenix/Elixir release on the target host."

  use HostKit.Recipe

  alias HostKit.Naming

  @default_erlang "27.2"
  @default_elixir "1.18.2-otp-27"
  @scope_key {__MODULE__, :scope}
  @ecto_key {__MODULE__, :ecto}

  defmacro elixir_app(name, do: block) do
    quote do
      HostKit.Recipes.ElixirApp.start_scope()
      unquote(block)
      opts = HostKit.Recipes.ElixirApp.finish_scope()
      elixir_app(unquote(name), opts)
    end
  end

  defmacro source(opts) do
    quote do
      HostKit.Recipes.ElixirApp.put_scope(:source, unquote(opts))
    end
  end

  defmacro phoenix(opts) do
    quote do
      HostKit.Recipes.ElixirApp.put_scope(:phoenix, unquote(opts))
    end
  end

  defmacro runtime(opts) do
    quote do
      HostKit.Recipes.ElixirApp.put_scope(:runtime, unquote(opts))
    end
  end

  defmacro release(opts) do
    quote do
      HostKit.Recipes.ElixirApp.put_scope(:release, unquote(opts))
    end
  end

  defmacro caddy(opts) do
    quote do
      HostKit.Recipes.ElixirApp.put_scope(:caddy, unquote(opts))
    end
  end

  defmacro ecto(opts) do
    quote do
      HostKit.Recipes.ElixirApp.put_scope(:ecto, unquote(opts))
    end
  end

  defmacro ecto(opts, do: block) do
    quote do
      HostKit.Recipes.ElixirApp.start_ecto(unquote(opts))
      unquote(block)
      HostKit.Recipes.ElixirApp.finish_ecto()
    end
  end

  defmacro repo(name) do
    quote do
      HostKit.Recipes.ElixirApp.add_ecto_repo(unquote(name))
    end
  end

  def start_scope do
    Process.put(@scope_key, [])
    :ok
  end

  def finish_scope do
    Process.delete(@scope_key) || raise "no elixir_app recipe scope"
  end

  def put_scope(key, value) when is_atom(key) do
    opts = Process.get(@scope_key) || raise "no elixir_app recipe scope"
    Process.put(@scope_key, Keyword.put(opts, key, value))
    :ok
  end

  def start_ecto(opts) do
    Process.put(@ecto_key, Keyword.put_new(opts, :repos, []))
    :ok
  end

  def add_ecto_repo(name) do
    opts = Process.get(@ecto_key) || raise "repo/1 is only available inside ecto/2"
    Process.put(@ecto_key, Keyword.update!(opts, :repos, &(&1 ++ [name])))
    :ok
  end

  def finish_ecto do
    opts = Process.delete(@ecto_key) || raise "no elixir_app ecto scope"
    put_scope(:ecto, opts)
  end

  defmacro mix(name, command_line, opts \\ []) do
    quote do
      command(
        unquote(name),
        unquote(opts)
        |> Keyword.put_new(:runtime, {:mise, :beam})
        |> Keyword.put(:exec, HostKit.Recipes.ElixirApp.mix_exec(unquote(command_line)))
      )
    end
  end

  def mix_exec(%HostKit.CommandLine{} = command), do: {"mix", [command.command | command.args]}

  def mix_exec(command) when is_binary(command),
    do: command |> HostKit.CommandLine.parse!() |> mix_exec()

  def mix_exec(args) when is_list(args), do: ["mix" | args]

  defrecipe elixir_app(name, opts) do
    app = __MODULE__.assigns(name, opts)

    service app.service_name do
      packages([:git, :curl, :ca_certificates])
      package(:caddy, as: "caddy")
      package(:build_essential, as: "build-essential")

      mise name: :beam, packages: app.runtime.mise_packages do
        tool(:erlang, app.runtime.erlang)
        tool(:elixir, app.runtime.elixir)
      end

      directory(app.paths.base, owner: "root", group: "root", mode: 0o755)
      directory(Path.dirname(app.paths.env), owner: "root", group: "root", mode: 0o755)

      dotenv app.paths.env, owner: "root", group: "root", mode: 0o600 do
        set("MIX_ENV", "prod")
        set("PHX_HOST", app.phoenix.host)
        set("PORT", to_string(app.phoenix.port))
        set("RELEASE_DISTRIBUTION", "none")
        set("SECRET_KEY_BASE", app.phoenix.secret_key_base)
      end

      source(app.source.name,
        git: app.source.repo,
        ref: app.source.ref,
        checkout: app.paths.source,
        path: app.source.path,
        dirty: :reset
      )

      mix(
        app.commands.deps.name,
        ~SH"deps.get --only prod",
        cwd: app.paths.app_dir,
        env: %{"MIX_ENV" => "prod"},
        inputs: [app.source.name, "mix.exs", "mix.lock"],
        outputs: ["deps"],
        timeout: 300_000
      )

      mix(
        app.commands.assets.name,
        ~SH"assets.deploy",
        cwd: app.paths.app_dir,
        env: %{"MIX_ENV" => "prod"},
        unless: "test ! -f mix.exs || ! grep -q assets.deploy mix.exs",
        timeout: 300_000
      )

      mix(
        app.commands.release.name,
        ~SH"release",
        cwd: app.paths.app_dir,
        env: %{"MIX_ENV" => "prod"},
        creates: app.paths.release_bin,
        inputs: [app.source.name, "mix.exs", "mix.lock", "lib", "config"],
        outputs: [app.paths.release_bin],
        timeout: 300_000
      )

      for ecto <- app.ecto do
        command(ecto.name,
          exec: HostKit.Recipes.ElixirApp.release_eval_exec(app, ecto.migrate),
          down: [exec: HostKit.Recipes.ElixirApp.release_eval_exec(app, ecto.rollback)],
          phase: :before_start,
          depends_on: [{:command, app.commands.release.name}],
          timeout: ecto.timeout
        )
      end

      endpoint(:http,
        port: app.phoenix.port,
        protocol: :http,
        health: app.health.path
      )

      daemon app.paths.service_unit do
        description("#{app.name} Elixir release")
        environment_file(app.paths.env)
        working_directory(app.paths.app_dir)
        exec_start([app.paths.release_bin, "start"])
        service(kill_mode: :mixed, timeout_stop_sec: 10)
        restart(:on_failure)
        wanted_by(:multi_user)
      end

      ready app.commands.ready.name, timeout: app.health.timeout do
        systemd(app.paths.service_unit, restart: true, kill: true)
        http(app.health.url, body: app.health.expect_body)
      end

      ingress app.service_name do
        server app.caddy.listen do
          route host: app.caddy.host do
            proxy(to: endpoint(app.service_name, :http))
          end
        end
      end
    end
  end

  def assigns(name, opts) when is_atom(name) do
    app_name = Naming.identity_segment(name)
    source = Keyword.fetch!(opts, :source)
    phoenix = Keyword.fetch!(opts, :phoenix)
    phoenix_host = Keyword.fetch!(phoenix, :host)
    runtime = Keyword.get(opts, :runtime, [])
    release = Keyword.get(opts, :release, [])
    caddy = Keyword.get(opts, :caddy, [])
    ecto = Keyword.get(opts, :ecto)

    app = %{
      name: app_name,
      service_name: name,
      release_name: Naming.elixir_release(Keyword.get(release, :name, app_name)),
      source: Map.put(normalize_source(source), :name, name),
      runtime: %{
        erlang: Keyword.get(runtime, :erlang, @default_erlang),
        elixir: Keyword.get(runtime, :elixir, @default_elixir),
        mise_packages: Keyword.get(runtime, :mise_packages, mise_beam_packages())
      },
      phoenix: %{
        host: phoenix_host,
        port: Keyword.get(phoenix, :port, 4000),
        secret_key_base: secret_key_base(Keyword.get(phoenix, :secret_key_base, :generate))
      },
      health: health(phoenix),
      caddy: %{
        host: Keyword.get(caddy, :host, phoenix_host),
        listen: Keyword.get(caddy, :listen, ":443")
      },
      ecto: normalize_ecto(ecto, app_name)
    }

    paths = paths(app)

    app
    |> Map.put(:paths, paths)
    |> Map.put(:commands, commands(app, paths))
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
      true -> raise ArgumentError, "elixir_app source expects :url, :git, or :github"
    end
  end

  defp paths(app) do
    base = "/opt/hostkit/apps/#{app.name}"
    source = Path.join(base, "source")
    app_dir = Path.expand(app.source.path, source)

    %{
      base: base,
      source: source,
      app_dir: app_dir,
      env: "/etc/hostkit/#{app.name}.env",
      service_unit: "#{app.name}.service",
      release_bin:
        Path.join([app_dir, "_build/prod/rel", app.release_name, "bin", app.release_name])
    }
  end

  defp commands(app, _paths) do
    %{
      source: %{name: command_name(app, :source)},
      deps: %{name: command_name(app, :deps)},
      assets: %{name: command_name(app, :assets)},
      release: %{name: command_name(app, :release)},
      ecto: %{name: command_name(app, :ecto_migrate)},
      ready: %{name: command_name(app, :ready)}
    }
  end

  def release_eval_exec(app, expression) do
    env_path = HostKit.Shell.escape(app.paths.env)
    release_bin = HostKit.Shell.escape(app.paths.release_bin)
    expression = HostKit.Shell.escape(expression)

    {"sh", ["-c", "set -a && . #{env_path} && set +a && exec #{release_bin} eval #{expression}"]}
  end

  defp normalize_ecto(nil, _app_name), do: []
  defp normalize_ecto(false, _app_name), do: []

  defp normalize_ecto(opts, app_name) when is_list(opts) do
    release = Keyword.fetch!(opts, :release)
    timeout = Keyword.get(opts, :timeout, 300_000)

    case Keyword.get(opts, :repos, []) do
      [] ->
        [
          %{
            name: Naming.resource([app_name, :ecto_migrate]),
            migrate: Keyword.get(opts, :migrate, "#{release}.migrate()"),
            rollback: Keyword.get(opts, :rollback, "#{release}.rollback()"),
            timeout: timeout
          }
        ]

      repos ->
        repos
        |> List.wrap()
        |> Enum.map(fn repo ->
          repo_name =
            repo |> to_string() |> String.split(".") |> List.last() |> Macro.underscore()

          %{
            name: Naming.resource([app_name, :ecto_migrate, repo_name]),
            migrate: "#{release}.migrate(#{repo})",
            rollback: "#{release}.rollback(#{repo})",
            timeout: timeout
          }
        end)
    end
  end

  defp health(phoenix) do
    path = Keyword.get(phoenix, :health_path, "/health")
    port = Keyword.get(phoenix, :port, 4000)

    %{
      path: path,
      url: "http://127.0.0.1:#{port}#{path}",
      expect_body: Keyword.get(phoenix, :health_body, "ok"),
      timeout: Keyword.get(phoenix, :health_timeout, 60_000)
    }
  end

  defp command_name(app, step), do: Naming.resource([app.name, step])

  defp mise_beam_packages do
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

  defp secret_key_base(:generate), do: Base.encode64(:crypto.strong_rand_bytes(64))
  defp secret_key_base(value), do: value
end
