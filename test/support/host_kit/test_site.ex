defmodule HostKit.TestSite do
  @moduledoc false

  defstruct host: nil, upstream: nil, depends_on: [], meta: %{}

  def id(%__MODULE__{host: host}), do: {:test_site, host}
end
