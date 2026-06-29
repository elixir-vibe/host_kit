defmodule HostKit.DSLCoreTest do
  use ExUnit.Case, async: true

  defmodule Fixture.Parent do
    defstruct items: []
    def add_item(parent, item), do: %{parent | items: parent.items ++ [item]}
  end

  defmodule Fixture do
    use HostKit.DSLCore

    scope :parent do
      accepts(:item)
    end

    scope(:flag, value: true)
  end

  test "scope generates conventional lifecycle helpers" do
    refute Fixture.flag_active?()

    assert Fixture.start_flag() == :ok
    assert Fixture.flag_active?()
    assert Fixture.finish_flag() == :ok
    refute Fixture.flag_active?()
  end

  test "scope generates state helpers" do
    assert Fixture.push_parent(%Fixture.Parent{}) == :ok
    assert Fixture.parent_active?()
    assert Fixture.current_parent!() == %Fixture.Parent{}

    assert Fixture.update_parent(&Fixture.Parent.add_item(&1, :one)) == :ok
    assert Fixture.pop_parent() == %Fixture.Parent{items: [:one]}
    refute Fixture.parent_active?()
  end

  test "scope records accepted children" do
    assert {:ok, scope} = Fixture.__dsl_core_scope__(:parent)
    assert scope.accepts == [%{name: :item, via: :add_item}]
  end

  test "attach updates the nearest active scope that accepts the child" do
    assert Fixture.push_parent(%Fixture.Parent{}) == :ok
    assert HostKit.DSLCore.attach(Fixture, :item, :attached) == :ok
    assert Fixture.pop_parent() == %Fixture.Parent{items: [:attached]}
  end

  test "use DSLCore provides caller-local attach helper" do
    assert Fixture.push_parent(%Fixture.Parent{}) == :ok
    assert Fixture.attach(:item, :local) == :ok
    assert Fixture.pop_parent() == %Fixture.Parent{items: [:local]}
  end
end
