defmodule HostKit.RuntimeSpecTest do
  use ExUnit.Case, async: true

  test "builds Unitctl specs through HostKit runtime alias" do
    assert {:ok, spec} =
             HostKit.Runtime.Spec.new(
               name: "host-kit-demo",
               command: ["/usr/bin/env", "true"],
               description: "HostKit demo",
               sandbox: %{no_new_privileges: true, private_tmp: true}
             )

    assert %Unitctl.Spec{} = spec
    assert HostKit.Runtime.Spec.unit_name(spec) == "host-kit-demo.service"
    assert [_ | _] = HostKit.Runtime.Spec.to_properties(spec)
  end
end
