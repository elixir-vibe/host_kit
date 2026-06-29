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
    scope(:partial, current: false, update: false)

    scope :child do
      requires(:parent)
    end
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

  test "scope can suppress selected helpers" do
    assert function_exported?(Fixture, :push_partial, 1)
    refute function_exported?(Fixture, :current_partial, 0)
    refute function_exported?(Fixture, :update_partial, 1)
  end

  test "scope records accepted children and required scopes" do
    assert {:ok, scope} = Fixture.__dsl_core_scope__(:parent)
    assert scope.accepts == [%{name: :item, via: :add_item}]

    assert {:ok, scope} = Fixture.__dsl_core_scope__(:child)
    assert scope.requires == [:parent]
  end

  test "scope requirements are enforced before push" do
    assert_raise ArgumentError, ~r/child must be declared inside parent/, fn ->
      Fixture.push_child(%{})
    end

    assert Fixture.push_parent(%Fixture.Parent{}) == :ok
    assert Fixture.push_child(%{}) == :ok
    assert Fixture.pop_child() == %{}
    assert Fixture.pop_parent() == %Fixture.Parent{}
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

  test "generated helpers raise readable inactive scope errors" do
    assert_raise ArgumentError, "no active parent scope", fn ->
      Fixture.pop_parent()
    end

    assert_raise ArgumentError, "no active parent scope", fn ->
      Fixture.current_parent!()
    end

    assert_raise ArgumentError, "parent directive used outside parent block", fn ->
      Fixture.update_parent(& &1)
    end
  end

  test "attach errors list acceptable parent scopes" do
    assert_raise ArgumentError, "item must be declared inside parent", fn ->
      Fixture.attach(:item, :missing_parent)
    end
  end
end
