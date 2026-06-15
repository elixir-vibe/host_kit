defmodule HostKit.ConfigFileTest do
  use HostKit.Case, async: false

  alias HostKit.Change
  alias HostKit.Resources.ConfigFile

  test "INI config renders deterministic sections and keys" do
    config =
      ConfigFile.new("/etc/app.ini", :ini,
        content: %{
          "server" => %{"HTTP_PORT" => 3000, "DOMAIN" => "git.elixir.toys"},
          "database" => %{"DB_TYPE" => "sqlite3", "LOG_SQL" => false}
        }
      )

    assert ConfigFile.render(config) ==
             {:ok,
              "[database]\nDB_TYPE=sqlite3\nLOG_SQL=false\n\n[server]\nDOMAIN=git.elixir.toys\nHTTP_PORT=3000\n"}
  end

  test "YAML config renders deterministic maps and lists" do
    config =
      ConfigFile.new("/etc/gatus.yaml", :yaml,
        content: %{
          "storage" => %{"type" => "sqlite", "path" => "/var/lib/gatus/gatus.db"},
          "endpoints" => [
            %{
              "name" => "Forgejo",
              "url" => "https://git.elixir.toys",
              "conditions" => ["[STATUS] == 200"]
            }
          ]
        }
      )

    assert ConfigFile.render(config) ==
             {:ok,
              "\"endpoints\":\n  - \"conditions\":\n      - \"[STATUS] == 200\"\n    \"name\": \"Forgejo\"\n    \"url\": \"https://git.elixir.toys\"\n\"storage\":\n  \"path\": \"/var/lib/gatus/gatus.db\"\n  \"type\": \"sqlite\"\n"}
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
    project = project_with_config(path, :yaml, %{"debug" => true, "port" => 8080})

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert {:ok, [%{status: :applied}]} = HostKit.apply(plan, confirm: true)

    assert File.read!(path) == "\"debug\": true\n\"port\": 8080\n"
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
