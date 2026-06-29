defmodule HostKit.Providers.Gatus.DSL do
  @moduledoc "DSL macros for Gatus config resources."

  use DSL.Macros

  alias HostKit.DSL.Scope, as: HostScope
  alias HostKit.Providers.Gatus.Scope

  defblock gatus_config(path, opts \\ []) do
    start(Scope.start_config(path, opts))
    finish(HostScope.add_resource(Scope.finish_config()))
  end

  defblock telegram_alerting(opts \\ []) do
    start(Scope.start_telegram_alerting(opts))
    finish(Scope.finish_telegram_alerting())
  end

  defdirective web(opts) do
    Scope.put_web(opts)
  end

  defdirective gatus_storage(type, opts) do
    Scope.put_storage(type, opts)
  end

  defdirective default_alert(opts) do
    Scope.put_default_alert(opts)
  end

  defdirective gatus_endpoint(name, opts) do
    Scope.add_endpoint(name, opts)
  end

  defdirective gatus_endpoints(endpoints) do
    Scope.add_endpoints(endpoints)
  end

  defdirective gatus_monitor_endpoints(opts \\ []) do
    Scope.add_monitor_endpoints(opts)
  end
end
