defmodule HostKit.Resource do
  @moduledoc "Helpers for resource identity and dependency metadata."

  @callback id(struct()) :: term()

  @spec id(struct()) :: term()
  def id(resource) do
    Code.ensure_loaded?(resource.__struct__)

    if function_exported?(resource.__struct__, :id, 1) do
      resource.__struct__.id(resource)
    else
      Map.fetch!(resource, :id)
    end
  end
end
