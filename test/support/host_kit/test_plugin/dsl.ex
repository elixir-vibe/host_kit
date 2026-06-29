defmodule HostKit.TestPlugin.DSL do
  @moduledoc false

  use DSL.Macros

  defblock test_site(host) do
    start(HostKit.TestPlugin.Scope.start_site(host))
    finish(HostKit.DSL.Scope.add_resource(HostKit.TestPlugin.Scope.finish_site()))
  end

  defdirective reverse_proxy(upstream) do
    HostKit.TestPlugin.Scope.put_upstream(upstream)
  end
end
