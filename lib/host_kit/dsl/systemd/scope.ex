defmodule HostKit.DSL.Systemd.Scope do
  @moduledoc false

  @service_key {__MODULE__, :service}
  @timer_key {__MODULE__, :timer}

  def start_service(name, opts) do
    Process.put(@service_key, %HostKit.Systemd.Service{
      name: name,
      unit: Keyword.get(opts, :unit, []),
      service: Keyword.get(opts, :service, []),
      install: Keyword.get(opts, :install, [])
    })
  end

  def finish_service do
    Process.delete(@service_key) || raise "no systemd service in scope"
  end

  def start_timer(name, opts) do
    Process.put(@timer_key, %HostKit.Systemd.Timer{
      name: name,
      unit: Keyword.get(opts, :unit, []),
      timer: Keyword.get(opts, :timer, []),
      install: Keyword.get(opts, :install, [])
    })
  end

  def finish_timer do
    Process.delete(@timer_key) || raise "no systemd timer in scope"
  end

  def put_unit(values), do: update_current(&%{&1 | unit: merge_directives(&1.unit, values)})
  def put_unit(key, value), do: update_current(&%{&1 | unit: put_directive(&1.unit, key, value)})

  def put_service(values),
    do: update(:service, &%{&1 | service: merge_directives(&1.service, values)})

  def put_service(key, value),
    do:
      update(
        :service,
        &%{&1 | service: put_directive(&1.service, key, normalize_value(key, value))}
      )

  def put_timer(values), do: update(:timer, &%{&1 | timer: merge_directives(&1.timer, values)})

  def put_timer(key, value),
    do: update(:timer, &%{&1 | timer: put_directive(&1.timer, key, normalize_value(key, value))})

  def put_install(values),
    do: update_current(&%{&1 | install: Keyword.merge(&1.install, normalize_values(values))})

  def put_install(key, value),
    do: update_current(&%{&1 | install: Keyword.put(&1.install, key, value)})

  def apply_hardening(:web_service) do
    update(:service, fn service ->
      hardened =
        service.service
        |> Keyword.put(:no_new_privileges, true)
        |> Keyword.put(:private_tmp, true)
        |> Keyword.put(:protect_system, :full)
        |> Keyword.put(:protect_home, true)

      %{service | service: hardened}
    end)
  end

  def apply_hardening(level),
    do: raise(ArgumentError, "unknown systemd hardening preset: #{inspect(level)}")

  defp update_current(fun) do
    cond do
      Process.get(@service_key) -> update(:service, fun)
      Process.get(@timer_key) -> update(:timer, fun)
      true -> raise "no systemd unit in scope"
    end
  end

  defp update(:service, fun) do
    service = Process.get(@service_key) || raise "no systemd service in scope"
    Process.put(@service_key, fun.(service))
    :ok
  end

  defp update(:timer, fun) do
    timer = Process.get(@timer_key) || raise "no systemd timer in scope"
    Process.put(@timer_key, fun.(timer))
    :ok
  end

  defp merge_directives(keywords, values) do
    Keyword.merge(keywords, normalize_values(values))
  end

  defp normalize_values(values) do
    Enum.map(values, fn {key, value} -> {key, normalize_value(key, value)} end)
  end

  defp put_directive(keywords, key, values)
       when is_list(values) and key in [:after, :wants, :read_write_paths] do
    Keyword.put(keywords, key, values)
  end

  defp put_directive(keywords, key, value), do: Keyword.put(keywords, key, value)

  defp normalize_value(:exec_start, argv) when is_list(argv), do: Enum.join(argv, " ")
  defp normalize_value(:restart, :on_failure), do: "on-failure"
  defp normalize_value(:on_calendar, value), do: HostKit.Systemd.Calendar.name(value)
  defp normalize_value(_key, value), do: value
end
