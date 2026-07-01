defmodule HostKit.CommandAnalysisTest do
  use ExUnit.Case, async: true

  test "plan returns structured diagnostics for missing command providers" do
    project = %HostKit.Project{
      name: :missing_command,
      services: [
        %HostKit.Service{
          name: :demo,
          resources: [
            HostKit.Resources.Command.new(:download, exec: ["wget", "https://example.com/file"])
          ]
        }
      ]
    }

    assert {:error, %HostKit.Diagnostics{errors: [diagnostic]}} = HostKit.plan(project)

    assert %HostKit.Diagnostic{
             severity: :error,
             code: :missing_command_provider,
             message: "command \"wget\" is required but not provided",
             resource_id: {:command, :download},
             details: %{command: "wget", required_by: {:command, :download}}
           } = diagnostic

    assert diagnostic.hint =~ "package :wget"
  end

  test "package provides satisfy command requirements" do
    project = %HostKit.Project{
      name: :provided_command,
      services: [
        %HostKit.Service{
          name: :demo,
          resources: [
            HostKit.Resources.Package.new(:wget),
            HostKit.Resources.Command.new(:download, exec: ["wget", "https://example.com/file"])
          ]
        }
      ]
    }

    assert {:ok, %HostKit.Plan{}} = HostKit.plan(project)
  end

  test "package provides override supports packages whose commands differ from package name" do
    project = %HostKit.Project{
      name: :provided_override,
      services: [
        %HostKit.Service{
          name: :demo,
          resources: [
            HostKit.Resources.Package.new(:postgresql_client,
              as: "postgresql-client",
              provides: ["psql"]
            ),
            HostKit.Resources.Command.new(:query, exec: ["psql", "--version"])
          ]
        }
      ]
    }

    assert {:ok, %HostKit.Plan{}} = HostKit.plan(project)
  end

  test "absolute path executables do not require package providers" do
    project = %HostKit.Project{
      name: :absolute_command,
      services: [
        %HostKit.Service{
          name: :demo,
          resources: [
            HostKit.Resources.Command.new(:migrate,
              exec: {"/opt/app/current/bin/app", ["eval", "App.Release.migrate()"]}
            )
          ]
        }
      ]
    }

    assert {:ok, %HostKit.Plan{}} = HostKit.plan(project)
  end

  test "mise beam runtime satisfies mix commands" do
    mise =
      HostKit.Resources.Mise.new(name: :beam, packages: false)
      |> HostKit.Resources.Mise.add_tool(:erlang, "27.2")
      |> HostKit.Resources.Mise.add_tool(:elixir, "1.18.2-otp-27")

    project = %HostKit.Project{
      name: :provided_by_mise,
      services: [
        %HostKit.Service{
          name: :demo,
          resources: [
            mise,
            HostKit.Resources.Command.new(:deps,
              exec: ["mix", "deps.get", "--only", "prod"],
              runtime: {:mise, :beam}
            )
          ]
        }
      ]
    }

    assert {:ok, %HostKit.Plan{}} = HostKit.plan(project)
  end

  test "diagnostics render in compiler-like form" do
    diagnostic = %HostKit.Diagnostic{
      severity: :error,
      code: :missing_command_provider,
      message: "command \"wget\" is required but not provided",
      resource_id: {:command, :download},
      details: %{command: "wget"},
      hint: "Add `package :wget`."
    }

    rendered = HostKit.Diagnostics.Format.format(diagnostic)

    assert rendered =~ "error: command \"wget\" is required but not provided"
    assert rendered =~ "hint: Add `package :wget`."
  end
end
