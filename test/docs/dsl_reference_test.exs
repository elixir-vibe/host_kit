defmodule HostKit.Docs.DSLReferenceTest do
  use ExUnit.Case, async: true

  @dsl_modules [
    HostKit.DSL,
    HostKit.DSL.Systemd,
    HostKit.Providers.Caddy.DSL,
    HostKit.Recipes.ElixirApp
  ]

  test "public DSL macros are listed in the DSL directive inventory" do
    docs = File.read!("guides/reference/dsl-guidelines.md")

    undocumented =
      @dsl_modules
      |> Enum.flat_map(fn module ->
        module.__info__(:macros)
        |> Keyword.delete(:__using__)
        |> Keyword.keys()
      end)
      |> Enum.uniq()
      |> Enum.reject(&String.contains?(docs, "`#{&1}`"))

    assert undocumented == []
  end
end
