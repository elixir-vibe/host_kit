defmodule HostKit.Recipes.ElixirApp do
  @moduledoc "Recipe for building and running a Phoenix/Elixir release on the target host."

  use HostKit.Recipe

  @default_erlang "27.2"
  @default_elixir "1.18.2-otp-27"

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

      mise name: :beam do
        tool(:erlang, app.runtime.erlang)
        tool(:elixir, app.runtime.elixir)
      end

      directory(app.paths.base, owner: "root", group: "root", mode: 0o755)
      directory(Path.dirname(app.paths.env), owner: "root", group: "root", mode: 0o755)

      env_file app.paths.env, owner: "root", group: "root", mode: 0o600 do
        set("MIX_ENV", "prod")
        set("PHX_HOST", app.phoenix.host)
        set("PORT", to_string(app.phoenix.port))
        set("SECRET_KEY_BASE", app.phoenix.secret_key_base)
      end

      source(app.commands.source.name,
        git: app.source.repo,
        ref: app.source.ref,
        checkout: app.paths.source,
        path: app.source.path
      )

      mix(
        app.commands.deps.name,
        ~SH"deps.get --only prod",
        cwd: app.paths.app_dir,
        env: %{"MIX_ENV" => "prod"},
        inputs: [source_ref(app.commands.source.name), "mix.exs", "mix.lock"],
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
        inputs: [source_ref(app.commands.source.name), "mix.exs", "mix.lock", "lib", "config"],
        outputs: [app.paths.release_bin],
        timeout: 300_000
      )

      daemon app.paths.service_unit do
        description("#{app.name} Elixir release")
        environment_file(app.paths.env)
        working_directory(app.paths.app_dir)
        exec_start([app.paths.release_bin])
        restart(:on_failure)
        wanted_by(:multi_user)
      end

      caddy_site app.service_name, app.caddy.host do
        reverse_proxy("127.0.0.1:#{app.phoenix.port}")
      end
    end
  end

  def assigns(name, opts) when is_atom(name) do
    path_name = name |> to_string() |> String.replace("_", "-")
    source = Keyword.fetch!(opts, :source)
    phoenix = Keyword.fetch!(opts, :phoenix)
    phoenix_host = Keyword.fetch!(phoenix, :host)
    runtime = Keyword.get(opts, :runtime, [])
    release = Keyword.get(opts, :release, [])
    caddy = Keyword.get(opts, :caddy, [])

    app = %{
      name: path_name,
      service_name: name,
      release_name:
        release |> Keyword.get(:name, path_name) |> to_string() |> String.replace("-", "_"),
      source: normalize_source(source),
      runtime: %{
        erlang: Keyword.get(runtime, :erlang, @default_erlang),
        elixir: Keyword.get(runtime, :elixir, @default_elixir)
      },
      phoenix: %{
        host: phoenix_host,
        port: Keyword.get(phoenix, :port, 4000),
        secret_key_base: secret_key_base(Keyword.get(phoenix, :secret_key_base, :generate))
      },
      caddy: %{
        host: Keyword.get(caddy, :host, phoenix_host)
      }
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
      release_bin: Path.join([app_dir, "_build/prod/rel", app.release_name, "bin/server"])
    }
  end

  defp commands(app, _paths) do
    %{
      source: %{name: command_name(app, :source)},
      deps: %{name: command_name(app, :deps)},
      assets: %{name: command_name(app, :assets)},
      release: %{name: command_name(app, :release)}
    }
  end

  defp command_name(app, step), do: "#{app.name}_#{step}"

  defp secret_key_base(:generate), do: Base.encode64(:crypto.strong_rand_bytes(64))
  defp secret_key_base(value), do: value
end
