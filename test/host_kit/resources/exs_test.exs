defmodule HostKit.Resources.ExsTest do
  use ExUnit.Case, async: true

  alias HostKit.Resources.Exs

  test "renders quoted exs AST with value placeholders" do
    ast =
      Code.string_to_quoted!("""
      import Config

      config :my_app,
        url: unquote(value("https://example.com")),
        port: unquote(value(4000))
      """)

    assert {:ok, rendered} = Exs.render(Exs.new("/etc/app/runtime.exs", ast))
    assert rendered =~ "import Config"
    assert rendered =~ ~s(config :my_app, url: "https://example.com", port: 4000)
  end

  test "renders secret placeholders only at render time" do
    System.put_env("HOSTKIT_EXS_SECRET", "secret-value")
    on_exit(fn -> System.delete_env("HOSTKIT_EXS_SECRET") end)

    ast =
      Code.string_to_quoted!("""
      import Config

      config :my_app,
        secret_key_base: unquote(secret("SECRET_KEY_BASE", env: "HOSTKIT_EXS_SECRET"))
      """)

    exs = Exs.new("/etc/app/runtime.exs", ast)
    assert Exs.secret?(exs)
    assert {:ok, rendered} = Exs.render(exs)
    assert rendered =~ ~s(secret_key_base: "secret-value")
  end

  test "DSL captures exs blocks without evaluating them" do
    source = """
    use HostKit.DSL

    project :demo do
      service :web do
        exs "/etc/app/runtime.exs", owner: "root", group: "root", mode: 0o640 do
          import Config

          config :my_app,
            url: unquote(value("https://example.com"))
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services
    assert [%Exs{} = exs] = service.resources
    assert exs.path == "/etc/app/runtime.exs"
    assert exs.mode == 0o640
    assert {:ok, rendered} = Exs.render(exs)
    assert rendered =~ ~s(url: "https://example.com")
  end

  test "plans exs files as file-like resources" do
    root = Path.join(System.tmp_dir!(), "hostkit-exs-#{System.unique_integer([:positive])}")
    path = Path.join(root, "runtime.exs")

    project =
      HostKit.Project.new(:demo)
      |> HostKit.Project.add_service(
        HostKit.Service.new(:web,
          resources: [
            Exs.new(
              path,
              Code.string_to_quoted!("""
              import Config
              config :my_app, url: unquote(value("https://example.com"))
              """),
              mode: 0o640
            )
          ]
        )
      )

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%HostKit.Change{action: :create, after: %Exs{}}] = plan.changes

    assert {:ok, _results} = HostKit.apply(plan, confirm: true)
    assert File.read!(path) =~ ~s(url: "https://example.com")

    File.rm_rf!(root)
  end
end
