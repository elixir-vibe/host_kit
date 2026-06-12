defmodule HostKit.Runner.SSHTest do
  use ExUnit.Case, async: true

  test "module exists as a HostKit runner" do
    Code.ensure_loaded!(HostKit.Runner.SSH)

    assert function_exported?(HostKit.Runner.SSH, :cmd, 3)
    assert function_exported?(HostKit.Runner.SSH, :mkdir_p, 2)
    assert function_exported?(HostKit.Runner.SSH, :write_file, 3)
  end

  test "connection runner exposes reusable connection API" do
    Code.ensure_loaded!(HostKit.Runner.SSH.Connection)

    assert function_exported?(HostKit.Runner.SSH.Connection, :open, 1)
    assert function_exported?(HostKit.Runner.SSH.Connection, :close, 1)
    assert function_exported?(HostKit.Runner.SSH.Connection, :cmd, 3)
  end
end
