defmodule HostKit.ApiTest do
  use ExUnit.Case, async: true

  test "exposes apply through top-level API" do
    plan = %HostKit.Plan{changes: []}

    assert HostKit.apply(plan, dry_run: true) == {:ok, []}
    assert HostKit.apply!(plan, dry_run: true) == []
  end

  test "exposes plan formatting through top-level API" do
    plan = %HostKit.Plan{changes: []}

    assert HostKit.format_plan(plan) ==
             "Plan: 0 to create, 0 to update, 0 to delete, 0 read errors, 0 unchanged"
  end

  test "provider namespace exposes Caddy provider" do
    assert HostKit.Providers.Caddy.provider_name() == :caddy
    assert HostKit.Providers.Caddy.dsl_modules() == [HostKit.Providers.Caddy.DSL]
    assert HostKit.Providers.Caddy.resource_types() == [HostKit.Caddy.Site]
  end
end
