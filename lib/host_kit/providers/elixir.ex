defmodule HostKit.Providers.Elixir do
  @moduledoc "Elixir application provider exposing Mix and Elixir app recipes."

  @behaviour HostKit.Provider

  @impl true
  def provider_name, do: :elixir

  @impl true
  def dsl_modules, do: [HostKit.Recipes.ElixirApp]

  @impl true
  def resource_types, do: []
end
