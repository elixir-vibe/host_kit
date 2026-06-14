defmodule HostKit.DSL.Readiness.Scope do
  @moduledoc false

  @key {__MODULE__, :readiness}

  def start(name, opts) do
    Process.put(@key, HostKit.Resources.Readiness.new(name, opts))
  end

  def finish do
    Process.delete(@key) || raise "no HostKit readiness in scope"
  end

  def active?, do: Process.get(@key) != nil

  def add_check(check) do
    readiness = Process.get(@key) || raise "readiness check used outside ready/2 block"
    Process.put(@key, %{readiness | checks: readiness.checks ++ [check]})
  end
end
