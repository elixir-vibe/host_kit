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

  test "builds remote target options from a declared host" do
    project = %HostKit.Project{
      name: :demo,
      hosts: [
        %HostKit.Host{
          name: :integration,
          hostname: "example.test",
          user: "root",
          sudo: true,
          meta: %{ssh: [port: 2222, identity_file: "/tmp/id", silently_accept_hosts: true]}
        }
      ]
    }

    opts = Options.target_opts([host: "integration"], project)
    target = Keyword.fetch!(opts, :target)

    assert target.opts[:host] == "example.test"
    assert target.opts[:user] == "root"
    assert target.opts[:sudo] == true
    assert target.opts[:port] == 2222
    assert target.opts[:identity_file] == "/tmp/id"
    assert target.opts[:silently_accept_hosts] == true
  end

  test "loads ssh settings from host DSL", %{env_var: env_var} do
    System.put_env(env_var, "secret")
    path = Path.join(System.tmp_dir!(), "hostkit-host-#{System.unique_integer([:positive])}.exs")

    File.write!(path, """
    use HostKit.DSL

    project :demo do
      host :integration, at: "example.test" do
        ssh port: 2222,
            user: "root",
            sudo: true,
            identity_file: "/tmp/id",
            password: secret_env(#{inspect(env_var)}),
            silently_accept_hosts: true
      end
    end
    """)

    on_exit(fn -> File.rm(path) end)

    project = HostKit.load!(path)
    opts = Options.target_opts([host: "integration"], project)
    target = Keyword.fetch!(opts, :target)

    assert target.opts[:port] == 2222
    assert target.opts[:identity_file] == "/tmp/id"
    assert target.opts[:password] == "secret"
    assert target.opts[:silently_accept_hosts] == true
  end

  test "does not add a nil password for host SSH settings" do
    project = %HostKit.Project{
      name: :demo,
      hosts: [%HostKit.Host{name: :integration, hostname: "example.test", user: "root"}]
    }

    opts = Options.target_opts([host: "integration"], project)
    target = Keyword.fetch!(opts, :target)

    refute Keyword.has_key?(target.opts, :password)
  end
end
