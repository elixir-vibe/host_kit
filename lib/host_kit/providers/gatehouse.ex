defmodule HostKit.Providers.Gatehouse do
  @moduledoc "Gatehouse provider exposing Gatehouse deployment recipes."

  @behaviour HostKit.Provider

  @impl true
  def provider_name, do: :gatehouse

  @impl true
  def dsl_modules, do: [HostKit.Recipes.Gatehouse]

  @impl true
  def resource_types, do: []
end
