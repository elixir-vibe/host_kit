defmodule Mix.Tasks.HostKit.FactsTest do
  use HostKit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    Mix.Task.reenable("host_kit.facts")
    :ok
  end

  test "prints selected local facts as json" do
    output =
      capture_io(fn ->
        Mix.Task.run("host_kit.facts", ["--local", "--only", "os", "--format", "json"])
      end)

    assert {:ok, decoded} = Jason.decode(output)
    assert Map.has_key?(decoded, "os")
    refute Map.has_key?(decoded, "users")
  end
end
