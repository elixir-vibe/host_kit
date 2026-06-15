defmodule HostKit.Providers.Gatus.DSL do
  @moduledoc "DSL macros for Gatus config resources."

  defmacro gatus_config(path, opts \\ [], do: block) do
    quote do
      HostKit.Providers.Gatus.Scope.start_config(unquote(path), unquote(opts))
      unquote(block)
      HostKit.DSL.Scope.add_resource(HostKit.Providers.Gatus.Scope.finish_config())
    end
  end

  defmacro web(opts) do
    quote do
      HostKit.Providers.Gatus.Scope.put_web(unquote(opts))
    end
  end

  defmacro gatus_storage(type, opts) do
    quote do
      HostKit.Providers.Gatus.Scope.put_storage(unquote(type), unquote(opts))
    end
  end

  defmacro telegram_alerting(opts \\ [], do: block) do
    quote do
      HostKit.Providers.Gatus.Scope.start_telegram_alerting(unquote(opts))
      unquote(block)
      HostKit.Providers.Gatus.Scope.finish_telegram_alerting()
    end
  end

  defmacro default_alert(opts) do
    quote do
      HostKit.Providers.Gatus.Scope.put_default_alert(unquote(opts))
    end
  end

  defmacro gatus_endpoint(name, opts) do
    quote do
      HostKit.Providers.Gatus.Scope.add_endpoint(unquote(name), unquote(opts))
    end
  end

  defmacro gatus_endpoints(endpoints) do
    quote do
      HostKit.Providers.Gatus.Scope.add_endpoints(unquote(endpoints))
    end
  end

  defmacro gatus_monitor_endpoints(opts \\ []) do
    quote do
      HostKit.Providers.Gatus.Scope.add_monitor_endpoints(unquote(opts))
    end
  end
end
