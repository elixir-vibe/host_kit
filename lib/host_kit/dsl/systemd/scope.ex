defmodule HostKit.DSL.Systemd.Scope do
  @moduledoc false

  @service_key {__MODULE__, :service}
  @timer_key {__MODULE__, :timer}

  def start_service(name, opts) do
    Process.put(@service_key, HostKit.Systemd.Service.new(name, opts))
  end

  def finish_service do
    Process.delete(@service_key) || raise "no systemd service in scope"
  end

  def start_timer(name, opts) do
    Process.put(@timer_key, HostKit.Systemd.Timer.new(name, opts))
  end

  def finish_timer do
    Process.delete(@timer_key) || raise "no systemd timer in scope"
  end

  def active?, do: Process.get(@service_key) != nil or Process.get(@timer_key) != nil

  def put_monitor(type, opts) do
    update_current(fn resource ->
      check =
        HostKit.Monitor.check(
          type,
          Keyword.put(opts, :resource_id, HostKit.Resource.id(resource))
        )

      update_in(resource.meta[:monitor], &(List.wrap(&1) ++ [check]))
    end)
  end

  def put_telemetry(config) do
    update_current(&put_in(&1.meta[:telemetry], config))
  end

  def put_logs(config) do
    update_current(fn resource ->
      resource
      |> put_in([Access.key(:meta), :logs], config)
      |> apply_log_directives(config)
    end)
  end

  def put_network_policy(opts) do
    update_current(fn resource ->
      resource
      |> put_in([Access.key(:meta), :network_policy], Map.new(opts))
      |> apply_network_policy(opts)
    end)
  end

  def put_listen(port, opts) do
    listen = %{port: port, on: HostKit.Net.Addr.normalize!(Keyword.get(opts, :on, :loopback))}
    update_current(&update_in(&1.meta[:listen], fn values -> List.wrap(values) ++ [listen] end))
  end

  def put_unit(values), do: update_current(&%{&1 | unit: merge_directives(&1.unit, values)})
  def put_unit(key, value), do: update_current(&%{&1 | unit: put_directive(&1.unit, key, value)})

  def put_service(values),
    do: update(:service, &%{&1 | service: merge_directives(&1.service, values)})

  def put_service(key, value),
    do:
      update(
        :service,
        &%{
          &1
          | service:
              put_directive(&1.service, key, HostKit.Systemd.Directives.coerce_value(key, value))
        }
      )

  def put_timer(values), do: update(:timer, &%{&1 | timer: merge_directives(&1.timer, values)})

  def put_timer(key, value),
    do:
      update(
        :timer,
        &%{
          &1
          | timer:
              put_directive(&1.timer, key, HostKit.Systemd.Directives.coerce_value(key, value))
        }
      )

  def put_install(values),
    do:
      update_current(
        &%{&1 | install: Keyword.merge(&1.install, HostKit.Systemd.Directives.coerce(values))}
      )

  def put_install(key, value),
    do: update_current(&%{&1 | install: Keyword.put(&1.install, key, value)})

  def apply_sandbox(profile, opts \\ []) do
    sandbox =
      profile
      |> HostKit.Runtime.Sandbox.new()
      |> Map.merge(Map.new(Keyword.get(opts, :sandbox, [])))

    resources =
      profile
      |> HostKit.Runtime.Resources.new()
      |> Map.merge(Map.new(Keyword.get(opts, :resources, [])))

    values =
      HostKit.Runtime.Sandbox.to_systemd_service_options(sandbox) ++
        HostKit.Runtime.Resources.to_systemd_service_options(resources)

    put_service(values)

    update_current(
      &put_in(&1.meta[:sandbox], %{profile: profile, sandbox: sandbox, resources: resources})
    )
  end

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

  defp apply_log_directives(%HostKit.Systemd.Service{} = resource, config) when is_map(config) do
    stdout = Map.get(config, :stdout, :journal)
    stderr = Map.get(config, :stderr, :journal)

    service =
      resource.service
      |> Keyword.put(:standard_output, stdout)
      |> Keyword.put(:standard_error, stderr)
      |> maybe_put_syslog_identifier(Map.get(config, :identifier))

    %{resource | service: service}
  end

  defp apply_log_directives(resource, _config), do: resource

  defp apply_network_policy(%HostKit.Systemd.Service{} = resource, opts) do
    service =
      resource.service
      |> put_network_directive(
        :ip_address_deny,
        Keyword.get(opts, :deny),
        &HostKit.Net.Addr.systemd_deny/1
      )
      |> put_network_directive(
        :ip_address_allow,
        Keyword.get(opts, :allow),
        &HostKit.Net.Addr.systemd_allow/1
      )
      |> Keyword.put_new(:restrict_address_families, "AF_INET AF_INET6 AF_UNIX")

    %{resource | service: service}
  end

  defp apply_network_policy(resource, _opts), do: resource

  defp put_network_directive(service, _key, nil, _fun), do: service

  defp put_network_directive(service, key, values, fun) when is_list(values),
    do: Keyword.put(service, key, Enum.map(values, fun))

  defp put_network_directive(service, key, value, fun), do: Keyword.put(service, key, fun.(value))

  defp maybe_put_syslog_identifier(service, nil), do: service

  defp maybe_put_syslog_identifier(service, identifier),
    do: Keyword.put(service, :syslog_identifier, identifier)

  defp merge_directives(keywords, values) do
    Keyword.merge(keywords, HostKit.Systemd.Directives.coerce(values))
  end

  defp put_directive(keywords, key, values)
       when is_list(values) and key in [:after, :wants, :read_write_paths] do
    Keyword.put(keywords, key, values)
  end

  defp put_directive(keywords, key, value), do: Keyword.put(keywords, key, value)
end
