defmodule HostKit.DSL.Systemd do
  @moduledoc "DSL helpers for core systemd resources."

  use DSL.Macros

  alias HostKit.DSL.Scope, as: HostScope
  alias HostKit.DSL.Systemd.Scope

  defblock(systemd_service(name, opts \\ [])) do
    start(Scope.start_service(name, opts))
    finish(HostScope.add_resource(Scope.finish_service()))
  end

  defblock(systemd_timer(name, opts \\ [])) do
    start(Scope.start_timer(name, opts))
    finish(HostScope.add_resource(Scope.finish_timer()))
  end

  defmacro daemon(do: block) do
    quote do
      systemd_service unit_name() do
        unquote(block)
      end
    end
  end

  defmacro daemon(opts, do: block) when is_list(opts) do
    quote do
      systemd_service Keyword.get(unquote(opts), :unit, unit_name()),
                      Keyword.delete(unquote(opts), :unit) do
        unquote(block)
      end
    end
  end

  defmacro daemon(name, opts \\ [], do: block) do
    quote do
      systemd_service HostKit.DSL.Systemd.service_unit_name(unquote(name)), unquote(opts) do
        unquote(block)
      end
    end
  end

  defmacro job(name, opts \\ [], do: block) do
    quote do
      systemd_service HostKit.DSL.Systemd.service_unit_name(unquote(name)), unquote(opts) do
        unquote(block)
      end
    end
  end

  defmacro schedule(name, opts \\ [], do: block) do
    quote do
      systemd_timer HostKit.DSL.Systemd.timer_unit_name(unquote(name)), unquote(opts) do
        unquote(block)
      end
    end
  end

  defdirective(unit(opts)) do
    HostKit.DSL.Systemd.Scope.put_unit(opts)
  end

  defdirective(service(opts)) do
    HostKit.DSL.Systemd.Scope.put_service(HostKit.DSL.Systemd.normalize_account_refs(opts))
  end

  defdirective(run(opts)) do
    HostKit.DSL.Systemd.Scope.put_service(HostKit.DSL.Systemd.normalize_account_refs(opts))
  end

  defdirective(timer(opts)) do
    HostKit.DSL.Systemd.Scope.put_timer(opts)
  end

  defdirective(every(interval)) do
    HostKit.DSL.Systemd.Scope.put_timer(:on_calendar, HostKit.Systemd.Calendar.name(interval))
  end

  defdirective(daily(opts)) do
    HostKit.DSL.Systemd.Scope.put_timer(
      :on_calendar,
      HostKit.Systemd.Calendar.daily_at(Keyword.fetch!(opts, :at))
    )
  end

  defdirective(weekly(day, opts)) do
    HostKit.DSL.Systemd.Scope.put_timer(
      :on_calendar,
      HostKit.Systemd.Calendar.weekly_at(day, Keyword.fetch!(opts, :at))
    )
  end

  defdirective(monthly(opts)) do
    HostKit.DSL.Systemd.Scope.put_timer(
      :on_calendar,
      HostKit.Systemd.Calendar.monthly_at(Keyword.fetch!(opts, :day), Keyword.fetch!(opts, :at))
    )
  end

  defdirective(jitter(value)) do
    HostKit.DSL.Systemd.Scope.put_timer(:randomized_delay_sec, value)
  end

  defdirective(repeat_after(value)) do
    HostKit.DSL.Systemd.Scope.put_timer(:on_unit_active_sec, value)
  end

  defdirective(after_boot(value)) do
    HostKit.DSL.Systemd.Scope.put_timer(:on_boot_sec, value)
  end

  defdirective(persistent(value)) do
    HostKit.DSL.Systemd.Scope.put_timer(:persistent, value)
  end

  defdirective(on_boot(value)) do
    HostKit.DSL.Systemd.Scope.put_timer(:on_boot_sec, value)
  end

  defdirective(description(value)) do
    HostKit.DSL.Systemd.Scope.put_unit(:description, value)
  end

  defdirective(after_units(values)) do
    HostKit.DSL.Systemd.Scope.put_unit(:after, values)
  end

  defdirective(after_target(targets)) do
    HostKit.DSL.Systemd.Scope.put_unit(:after, HostKit.Systemd.Target.names(targets))
  end

  defdirective(wants(values)) do
    HostKit.DSL.Systemd.Scope.put_unit(:wants, HostKit.Systemd.Target.names(values))
  end

  defdirective(requires(values)) do
    HostKit.DSL.Systemd.Scope.put_unit(:requires, HostKit.Systemd.Target.names(values))
  end

  defdirective(service_user(value)) do
    HostKit.DSL.Systemd.Scope.put_service(:user, HostKit.Account.name!(value))
  end

  defdirective(service_group(value)) do
    HostKit.DSL.Systemd.Scope.put_service(:group, HostKit.Account.name!(value))
  end

  defdirective(working_directory(value)) do
    HostKit.DSL.Systemd.Scope.put_service(:working_directory, value)
  end

  defdirective(environment_file(value)) do
    HostKit.DSL.Systemd.Scope.put_service(:environment_file, value)
  end

  defdirective(exec_start(value)) do
    HostKit.DSL.Systemd.Scope.put_service(:exec_start, value)
  end

  defdirective(exec(value)) do
    HostKit.DSL.Systemd.Scope.put_service(:exec_start, value)
  end

  defdirective(exec_stop(value)) do
    HostKit.DSL.Systemd.Scope.put_service(:exec_stop, value)
  end

  defdirective(restart(value)) do
    HostKit.DSL.Systemd.Scope.put_service(:restart, value)
  end

  defdirective(restart_sec(value)) do
    HostKit.DSL.Systemd.Scope.put_service(:restart_sec, value)
  end

  defdirective(install(opts)) do
    HostKit.DSL.Systemd.Scope.put_install(opts)
  end

  defdirective(wanted_by(targets)) do
    HostKit.DSL.Systemd.Scope.put_install(:wanted_by, HostKit.Systemd.Target.names(targets))
  end

  defdirective(hardening(level)) do
    HostKit.DSL.Systemd.Scope.apply_hardening(level)
  end

  defdirective(read_write_paths(paths)) do
    HostKit.DSL.Systemd.Scope.put_service(:read_write_paths, paths)
  end

  def service_unit_name(name), do: unit_name(name, ".service")
  def timer_unit_name(name), do: unit_name(name, ".timer")

  defp unit_name(name, suffix) when is_atom(name) do
    identity = HostKit.Naming.identity_segment(name)

    :unit
    |> HostScope.prefixed(identity)
    |> HostKit.Naming.systemd_unit(suffix)
  end

  defp unit_name(name, suffix), do: HostKit.Naming.systemd_unit(name, suffix)

  def normalize_account_refs(opts) when is_list(opts) do
    opts
    |> Keyword.update(:user, nil, &HostKit.Account.name!/1)
    |> Keyword.update(:group, nil, &HostKit.Account.name!/1)
    |> Enum.reject(&match?({_key, nil}, &1))
  end
end
