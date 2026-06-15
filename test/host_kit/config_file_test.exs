defmodule HostKit.ConfigFileTest do
  use HostKit.Case, async: false

  alias HostKit.Change
  alias HostKit.Resources.ConfigFile

  test "INI config renders deterministic sections and keys" do
    config =
      ConfigFile.new("/etc/app.ini", :ini,
        content: [
          database: [DB_TYPE: "sqlite3", LOG_SQL: false],
          server: [DOMAIN: "git.elixir.toys", HTTP_PORT: 3000]
        ]
      )

    assert ConfigFile.render(config) ==
             {:ok,
              "[database]\nDB_TYPE=sqlite3\nLOG_SQL=false\n\n[server]\nDOMAIN=git.elixir.toys\nHTTP_PORT=3000\n"}
  end

  test "YAML config renders deterministic maps and lists" do
    config =
      ConfigFile.new("/etc/gatus.yaml", :yaml,
        content: [
          endpoints: [
            [
              name: "Forgejo",
              url: "https://git.elixir.toys",
              conditions: ["[STATUS] == 200"]
            ]
          ],
          storage: [type: "sqlite", path: "/var/lib/gatus/gatus.db"]
        ]
      )

    assert ConfigFile.render(config) ==
             {:ok,
              "endpoints:\n  - name: Forgejo\n    url: https://git.elixir.toys\n    conditions:\n      - '[STATUS] == 200'\n\nstorage:\n  type: sqlite\n  path: /var/lib/gatus/gatus.db\n"}
  end

  test "INI block DSL builds structured config" do
    project =
      Code.eval_string("""
      use HostKit.DSL

      project :config do
        roots config: "/etc"

        service :forgejo do
          ini path(:config, "app.ini"), owner: "root", group: service_user(), mode: 0o640 do
            section "server" do
              set "DOMAIN", "git.elixir.toys"
              set "HTTP_PORT", 3000
            end
          end
        end
      end
      """)
      |> elem(0)

    assert [%ConfigFile{format: :ini, content: %{"server" => server}, group: "forgejo"}] =
             HostKit.Project.resources(project)

    assert server == %{"DOMAIN" => "git.elixir.toys", "HTTP_PORT" => 3000}
  end

  test "INI config supports top-level keys" do
    config =
      ConfigFile.new("/etc/app.ini", :ini,
        content: [APP_NAME: "demo", server: [DOMAIN: "example.com"]]
      )

    assert ConfigFile.render(config) == {:ok, "APP_NAME=demo\n\n[server]\nDOMAIN=example.com\n"}
  end

  test "secret INI config compares only public entries" do
    path = Path.join(tmp_dir("config-file-secret-plan"), "app.ini")

    File.write!(path, """
    APP_NAME = elixir.toys git

    [server]
    DOMAIN=git.elixir.toys
    LFS_JWT_SECRET=actual-secret
    """)

    project =
      project_with_config(path, :ini,
        APP_NAME: "elixir.toys git",
        server: [DOMAIN: "git.elixir.toys", LFS_JWT_SECRET: :redacted]
      )

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%Change{action: :no_op, resource_id: {:ini, ^path}}] = plan.changes
  after
    cleanup_tmp("config-file-secret-plan")
  end

  test "secret YAML config compares only public paths" do
    path = Path.join(tmp_dir("config-file-secret-yaml-plan"), "gatus.yaml")

    File.write!(path, """
    alerting:
      telegram:
        token: actual-secret
        id: chat-id
    endpoints:
      - name: Forgejo
        url: https://git.elixir.toys
    """)

    project =
      project_with_config(path, :yaml,
        alerting: [telegram: [token: :redacted, id: "chat-id"]],
        endpoints: [[name: "Forgejo", url: "https://git.elixir.toys"]]
      )

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%Change{action: :no_op, resource_id: {:yaml, ^path}}] = plan.changes
  after
    cleanup_tmp("config-file-secret-yaml-plan")
  end

  test "secret YAML plan detects public path drift" do
    path = Path.join(tmp_dir("config-file-secret-yaml-drift"), "gatus.yaml")

    File.write!(path, """
    alerting:
      telegram:
        token: actual-secret
        id: old-chat-id
    """)

    project =
      project_with_config(path, :yaml,
        alerting: [telegram: [token: :redacted, id: "new-chat-id"]]
      )

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%Change{action: :update, resource_id: {:yaml, ^path}} = change] = plan.changes
    assert HostKit.Plan.Format.format_change(change) =~ "public keys: alerting.telegram.id"
    assert HostKit.Plan.Format.format_change(change) =~ "redacted keys: alerting.telegram.token"
  after
    cleanup_tmp("config-file-secret-yaml-drift")
  end

  test "redacted structured configs are not renderable" do
    config = ConfigFile.new("/etc/app.ini", :ini, content: [server: [TOKEN: :redacted]])

    assert ConfigFile.render(config) == {:error, :redacted_secret_not_renderable}
  end

  test "secret config rendering resolves env-backed secrets" do
    env = "HOSTKIT_CONFIG_FILE_SECRET"
    System.put_env(env, "actual-secret")

    config =
      ConfigFile.new("/etc/app.ini", :ini,
        content: [server: [DOMAIN: "git.elixir.toys", LFS_JWT_SECRET: HostKit.Secret.env(env)]]
      )

    assert ConfigFile.render(config) ==
             {:ok, "[server]\nDOMAIN=git.elixir.toys\nLFS_JWT_SECRET=actual-secret\n"}
  after
    System.delete_env("HOSTKIT_CONFIG_FILE_SECRET")
  end

  test "plan compares rendered config content with managed file on disk" do
    path = Path.join(tmp_dir("config-file-plan"), "app.ini")
    File.write!(path, "[server]\nDOMAIN=git.elixir.toys\n")

    project = project_with_config(path, :ini, %{"server" => %{"DOMAIN" => "git.elixir.toys"}})

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%Change{action: :no_op, resource_id: {:ini, ^path}}] = plan.changes

    drifted = project_with_config(path, :ini, %{"server" => %{"DOMAIN" => "git.example.com"}})

    assert {:ok, plan} = HostKit.plan(drifted, reader: HostKit.Local)
    assert [%Change{action: :update, resource_id: {:ini, ^path}}] = plan.changes
  after
    cleanup_tmp("config-file-plan")
  end

  test "apply writes rendered structured config" do
    path = Path.join(tmp_dir("config-file-apply"), "etc/gatus.yaml")
    project = project_with_config(path, :yaml, debug: true, port: 8080)

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert {:ok, [%{status: :applied}]} = HostKit.apply(plan, confirm: true)

    assert File.read!(path) == "debug: true\n\nport: 8080\n"
  after
    cleanup_tmp("config-file-apply")
  end

  defp project_with_config(path, format, content) do
    %HostKit.Project{name: :config}
    |> HostKit.Project.add_resource(ConfigFile.new(path, format, content: content))
  end

  defp tmp_dir(name) do
    path = Path.join(System.tmp_dir!(), "hostkit-#{name}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp cleanup_tmp(name) do
    HostKit.SafeTmp.rm_rf!(Path.join(System.tmp_dir!(), "hostkit-#{name}"), "hostkit-")
  end
end
