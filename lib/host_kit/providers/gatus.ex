defmodule HostKit.Providers.Gatus do
  @moduledoc "Gatus provider helpers for structured monitoring config files."

  def provider_name, do: :gatus

  def dsl_modules, do: [HostKit.Providers.Gatus.DSL]
end
