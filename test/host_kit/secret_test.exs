defmodule HostKit.SecretTest do
  use ExUnit.Case, async: false

  test "resolves environment-backed secrets" do
    env_var = "HOSTKIT_SECRET_TEST_#{System.unique_integer([:positive])}"
    System.put_env(env_var, "secret")

    on_exit(fn -> System.delete_env(env_var) end)

    assert HostKit.Secret.env(env_var) |> HostKit.Secret.resolve!() == "secret"
  end

  test "raises for missing environment-backed secrets" do
    env_var = "HOSTKIT_SECRET_TEST_MISSING_#{System.unique_integer([:positive])}"

    assert_raise System.EnvError, fn ->
      env_var |> HostKit.Secret.env() |> HostKit.Secret.resolve!()
    end
  end

  test "leaves non-secret values unchanged" do
    assert HostKit.Secret.resolve!("plain") == "plain"
    assert HostKit.Secret.resolve!(nil) == nil
  end
end
