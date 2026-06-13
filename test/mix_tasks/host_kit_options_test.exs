defmodule Mix.Tasks.HostKit.OptionsTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.HostKit.Options

  setup do
    env_var = "HOSTKIT_TEST_SSH_PASSWORD_#{System.unique_integer([:positive])}"

    on_exit(fn -> System.delete_env(env_var) end)

    %{env_var: env_var}
  end

  test "reads remote password from --password-env", %{env_var: env_var} do
    System.put_env(env_var, "secret")

    opts = Options.target_opts(remote: "example.test", password_env: env_var)
    target = Keyword.fetch!(opts, :target)

    assert Keyword.fetch!(target.opts, :password) == "secret"
  end

  test "rejects missing --password-env", %{env_var: env_var} do
    assert_raise Mix.Error, ~r/environment variable #{env_var} is not set/, fn ->
      Options.target_opts(remote: "example.test", password_env: env_var)
    end
  end

  test "rejects --password with --password-env", %{env_var: env_var} do
    System.put_env(env_var, "secret")

    assert_raise Mix.Error, ~r/pass either --password or --password-env/, fn ->
      Options.target_opts(remote: "example.test", password: "secret", password_env: env_var)
    end
  end
end
