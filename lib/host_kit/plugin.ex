defmodule HostKit.Plugin do
  @moduledoc "Deprecated compatibility alias for `HostKit.Provider`."

  @deprecated "use HostKit.Provider instead"
  defdelegate resolve(opts_or_providers \\ []), to: HostKit.Provider

  @deprecated "use HostKit.Provider instead"
  defdelegate dsl_modules(providers), to: HostKit.Provider

  @deprecated "use HostKit.Provider instead"
  defdelegate render(providers, resource, context \\ %{}), to: HostKit.Provider

  @deprecated "use HostKit.Provider instead"
  defdelegate validate(providers, resource, context \\ %{}), to: HostKit.Provider
end
