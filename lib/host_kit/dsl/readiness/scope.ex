defmodule HostKit.DSL.Readiness.Scope do
  @moduledoc false

  use HostKit.DSLCore

  scope(:readiness)

  def start(name, opts) do
    push_readiness(HostKit.Resources.Readiness.new(name, opts))
  end

  def finish do
    pop_readiness()
  end

  def active?, do: readiness_active?()

  def add_check(check) do
    update_readiness(&%{&1 | checks: &1.checks ++ [check]})
  end
end
