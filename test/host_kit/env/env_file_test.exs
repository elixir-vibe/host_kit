defmodule HostKit.EnvFileTest do
  use ExUnit.Case, async: true

  test "env_file DSL builds redacted env file resources" do
    source = """
    use HostKit.DSL

    project :demo do
      service :web do
        env_file "/etc/app/env", owner: "root", group: "app", mode: 0o640 do
          set :mix_env, :prod
          set :PORT, 4000
          secret :SECRET_KEY_BASE, env: "HOST_KIT_TEST_SECRET"
          secret :GENERATED_TOKEN, env: :redacted
          secret :FILE_TOKEN, file: "/run/app/token"
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services
    assert [%HostKit.Resources.EnvFile{} = env_file] = service.resources
    assert env_file.path == "/etc/app/env"
    assert env_file.owner == "root"
    assert env_file.group == "app"
    assert env_file.mode == 0o640

    assert env_file.entries == [
             {:set, "MIX_ENV", "prod"},
             {:set, "PORT", "4000"},
             {:secret, "SECRET_KEY_BASE", HostKit.Secret.env("HOST_KIT_TEST_SECRET")},
             {:secret, "GENERATED_TOKEN", :redacted},
             {:secret, "FILE_TOKEN", HostKit.Secret.file("/run/app/token")}
           ]
  end

  test "renders dotenv content with secrets from environment" do
    env_file = %HostKit.Resources.EnvFile{
      path: "/etc/app/env",
      entries: [
        {:set, "MIX_ENV", "prod"},
        {:set, "URL", "https://example.com/a?b=c&d=e"},
        {:secret, "SECRET", HostKit.Secret.env("HOST_KIT_TEST_SECRET")}
      ]
    }

    System.put_env("HOST_KIT_TEST_SECRET", "hello # world")

    assert {:ok, content} = HostKit.Env.render(env_file)
    assert content =~ ~s(MIX_ENV="prod")
    assert content =~ ~s(URL="https://example.com/a?b=c&d=e")
    assert content =~ ~s(SECRET="hello # world")
  after
    System.delete_env("HOST_KIT_TEST_SECRET")
  end

  test "redacted env file secrets are not renderable" do
    env_file = %HostKit.Resources.EnvFile{
      path: "/etc/app/env",
      entries: [{:secret, "SECRET", :redacted}]
    }

    assert HostKit.Env.render(env_file) == {:error, :redacted_secret_not_renderable}
  end

  test "missing secret envs fail rendering" do
    env_file = %HostKit.Resources.EnvFile{
      path: "/etc/app/env",
      entries: [{:secret, "SECRET", HostKit.Secret.env("HOST_KIT_MISSING_SECRET")}]
    }

    assert HostKit.Env.render(env_file) ==
             {:error, {:missing_secret_env, "HOST_KIT_MISSING_SECRET"}}
  end

  test "env file plans compare metadata and non-secret entries" do
    desired = %HostKit.Resources.EnvFile{
      path: "/etc/app/env",
      owner: "root",
      group: "app",
      mode: 0o640
    }

    actual = %HostKit.Resources.EnvFile{
      path: "/etc/app/env",
      owner: "root",
      group: "app",
      mode: 0o640
    }

    project = %HostKit.Project{services: [%HostKit.Service{name: :web, resources: [desired]}]}

    defmodule EnvFileReader do
      def read(%HostKit.Resources.EnvFile{}, _context) do
        {:ok,
         %HostKit.Resources.EnvFile{
           path: "/etc/app/env",
           owner: "root",
           group: "app",
           mode: 0o640
         }}
      end
    end

    assert {:ok, plan} = HostKit.plan(project, reader: EnvFileReader)
    assert [%{action: :no_op, reason: :in_sync}] = plan.changes
  end

  test "env file plans update when public entries drift" do
    desired = %HostKit.Resources.EnvFile{
      path: "/etc/app/env",
      entries: [
        {:set, "PORT", "4001"},
        {:secret, "SECRET_KEY_BASE", HostKit.Secret.env("HOST_KIT_TEST_SECRET")}
      ],
      owner: "root",
      group: "app",
      mode: 0o640
    }

    project = %HostKit.Project{services: [%HostKit.Service{name: :web, resources: [desired]}]}

    defmodule EnvFileDriftReader do
      def read(%HostKit.Resources.EnvFile{} = desired, _context) do
        {:ok,
         %HostKit.Resources.EnvFile{
           desired
           | owner: "root",
             group: "app",
             mode: 0o640,
             meta: %{actual_public_entries: %{"PORT" => "4000"}}
         }}
      end
    end

    assert {:ok, plan} = HostKit.plan(project, reader: EnvFileDriftReader)
    assert [%{action: :update, reason: :drift}] = plan.changes
  end
end
