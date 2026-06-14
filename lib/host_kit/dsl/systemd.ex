defmodule HostKit.DSL.Systemd do
  @moduledoc "DSL helpers for core systemd resources."

  defmacro systemd_service(name, opts \\ [], do: block) do
    quote do
      HostKit.DSL.Systemd.Scope.start_service(unquote(name), unquote(opts))
      unquote(block)
      HostKit.DSL.Scope.add_resource(HostKit.DSL.Systemd.Scope.finish_service())
    end
  end

  defmacro systemd_timer(name, opts \\ [], do: block) do
    quote do
      HostKit.DSL.Systemd.Scope.start_timer(unquote(name), unquote(opts))
      unquote(block)
      HostKit.DSL.Scope.add_resource(HostKit.DSL.Systemd.Scope.finish_timer())
    end
  end

  defmacro daemon(name, opts \\ [], do: block) do
    quote do
      systemd_service unquote(name), unquote(opts) do
        unquote(block)
      end
    end
  end

  defmacro job(name, opts \\ [], do: block) do
    quote do
      systemd_service unquote(name), unquote(opts) do
        unquote(block)
      end
    end
  end

  defmacro schedule(name, opts \\ [], do: block) do
    quote do
      systemd_timer unquote(name), unquote(opts) do
        unquote(block)
      end
    end
  end

  defmacro unit(opts) do
    quote do
      HostKit.DSL.Systemd.Scope.put_unit(unquote(opts))
    end
  end

  defmacro service(opts) do
    quote do
      HostKit.DSL.Systemd.Scope.put_service(unquote(opts))
    end
  end

  defmacro run(opts) do
    quote do
      HostKit.DSL.Systemd.Scope.put_service(unquote(opts))
    end
  end

  defmacro timer(opts) do
    quote do
      HostKit.DSL.Systemd.Scope.put_timer(unquote(opts))
    end
  end

  defmacro every(interval) do
    quote do
      HostKit.DSL.Systemd.Scope.put_timer(
        :on_calendar,
        HostKit.Systemd.Calendar.name(unquote(interval))
      )
    end
  end

  defmacro persistent(value) do
    quote do
      HostKit.DSL.Systemd.Scope.put_timer(:persistent, unquote(value))
    end
  end

  defmacro on_boot(value) do
    quote do
      HostKit.DSL.Systemd.Scope.put_timer(:on_boot_sec, unquote(value))
    end
  end

  defmacro description(value) do
    quote do
      HostKit.DSL.Systemd.Scope.put_unit(:description, unquote(value))
    end
  end

  defmacro after_units(values) do
    quote do
      HostKit.DSL.Systemd.Scope.put_unit(:after, unquote(values))
    end
  end

  defmacro after_target(targets) do
    quote do
      HostKit.DSL.Systemd.Scope.put_unit(:after, HostKit.Systemd.Target.names(unquote(targets)))
    end
  end

  defmacro wants(values) do
    quote do
      HostKit.DSL.Systemd.Scope.put_unit(:wants, HostKit.Systemd.Target.names(unquote(values)))
    end
  end

  defmacro requires(values) do
    quote do
      HostKit.DSL.Systemd.Scope.put_unit(:requires, HostKit.Systemd.Target.names(unquote(values)))
    end
  end

  defmacro service_user(value) do
    quote do
      HostKit.DSL.Systemd.Scope.put_service(:user, HostKit.Account.name!(unquote(value)))
    end
  end

  defmacro service_group(value) do
    quote do
      HostKit.DSL.Systemd.Scope.put_service(:group, HostKit.Account.name!(unquote(value)))
    end
  end

  defmacro working_directory(value) do
    quote do
      HostKit.DSL.Systemd.Scope.put_service(:working_directory, unquote(value))
    end
  end

  defmacro environment_file(value) do
    quote do
      HostKit.DSL.Systemd.Scope.put_service(:environment_file, unquote(value))
    end
  end

  defmacro exec_start(value) do
    quote do
      HostKit.DSL.Systemd.Scope.put_service(:exec_start, unquote(value))
    end
  end

  defmacro exec_stop(value) do
    quote do
      HostKit.DSL.Systemd.Scope.put_service(:exec_stop, unquote(value))
    end
  end

  defmacro restart(value) do
    quote do
      HostKit.DSL.Systemd.Scope.put_service(:restart, unquote(value))
    end
  end

  defmacro restart_sec(value) do
    quote do
      HostKit.DSL.Systemd.Scope.put_service(:restart_sec, unquote(value))
    end
  end

  defmacro install(opts) do
    quote do
      HostKit.DSL.Systemd.Scope.put_install(unquote(opts))
    end
  end

  defmacro wanted_by(targets) do
    quote do
      HostKit.DSL.Systemd.Scope.put_install(
        :wanted_by,
        HostKit.Systemd.Target.names(unquote(targets))
      )
    end
  end

  defmacro hardening(level) do
    quote do
      HostKit.DSL.Systemd.Scope.apply_hardening(unquote(level))
    end
  end

  defmacro read_write_paths(paths) do
    quote do
      HostKit.DSL.Systemd.Scope.put_service(:read_write_paths, unquote(paths))
    end
  end
end
