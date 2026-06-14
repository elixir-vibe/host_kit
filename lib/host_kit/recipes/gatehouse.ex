defmodule HostKit.Recipes.Gatehouse do
  @moduledoc "Recipe for running an already-built Gatehouse release under systemd."

  use HostKit.Recipe

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

      env_file gatehouse.paths.env, owner: "root", group: "root", mode: 0o600 do
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

  def assigns(name, opts) when is_atom(name) or is_binary(name) do
    path_name = name |> to_string() |> String.replace("_", "-")
    release_path = Keyword.get(opts, :release_path, "/opt/gatehouse")
    config_path = Keyword.get(opts, :config_path, "/etc/gatehouse/config.exs")
    state_path = Keyword.get(opts, :state_path, "/var/lib/gatehouse/state.etf")
    env_path = Keyword.get(opts, :env_path, "/etc/gatehouse/env")
    service_unit = Keyword.get(opts, :service_unit, "gatehouse.service")

    %{
      name: path_name,
      service_name: Keyword.get(opts, :service, :gatehouse),
      owner: HostKit.Account.name!(Keyword.get(opts, :run_as, "gatehouse")),
      group:
        HostKit.Account.name!(Keyword.get(opts, :group, Keyword.get(opts, :run_as, "gatehouse"))),
      cookie: Keyword.get(opts, :cookie),
      ready_name: "gatehouse_#{path_name}_ready",
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
end
