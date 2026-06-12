defmodule HostKit.DSL.Systemd.Scope do
  @moduledoc false

  @service_key {__MODULE__, :service}

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

  def put_unit(key, value), do: update(&%{&1 | unit: put_directive(&1.unit, key, value)})

  def put_service(key, value),
    do: update(&%{&1 | service: put_directive(&1.service, key, normalize_value(key, value))})

  def put_install(values), do: update(&%{&1 | install: Keyword.merge(&1.install, values)})

  def apply_hardening(:web_service) do
    update(fn service ->
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

  defp update(fun) do
    service = Process.get(@service_key) || raise "no systemd service in scope"
    Process.put(@service_key, fun.(service))
    :ok
  end

  defp put_directive(keywords, key, values)
       when is_list(values) and key in [:after, :wants, :read_write_paths] do
    Keyword.put(keywords, key, values)
  end

  defp put_directive(keywords, key, value), do: Keyword.put(keywords, key, value)

  defp normalize_value(:exec_start, argv) when is_list(argv), do: Enum.join(argv, " ")
  defp normalize_value(:restart, :on_failure), do: "on-failure"
  defp normalize_value(_key, value), do: value
end
