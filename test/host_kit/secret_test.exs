defmodule HostKit.SecretTest do
  use ExUnit.Case, async: false

  test "resolves environment-backed secrets" do
    env_var = "HOSTKIT_SECRET_TEST_#{System.unique_integer([:positive])}"
    System.put_env(env_var, "secret")

    on_exit(fn -> System.delete_env(env_var) end)

    assert HostKit.Secret.env(env_var) |> HostKit.Secret.resolve!() == "secret"
  end

  test "resolves file-backed secrets" do
    path = Path.join(System.tmp_dir!(), "hostkit-secret-#{System.unique_integer([:positive])}")
    File.write!(path, "secret\n")
    on_exit(fn -> File.rm(path) end)

    assert path |> HostKit.Secret.file() |> HostKit.Secret.resolve!() == "secret"
  end

  test "resolves command-backed secrets" do
    assert ["sh", "-c", "printf secret"] |> HostKit.Secret.command() |> HostKit.Secret.resolve!() ==
             "secret"
  end

  test "builds secret sources from DSL-style options" do
    assert HostKit.Secret.from_opts!(env: :redacted) == :redacted
    assert HostKit.Secret.from_opts!(env: "APP_SECRET") == HostKit.Secret.env("APP_SECRET")
    assert HostKit.Secret.from_opts!(file: "/run/secret") == HostKit.Secret.file("/run/secret")

    assert HostKit.Secret.from_opts!(command: ["pass", "show", "app"]) ==
             HostKit.Secret.command(["pass", "show", "app"])
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
