defmodule HostKit.Resources.TemplateTest do
  use HostKit.Case, async: false

  alias HostKit.Change
  alias HostKit.Resources.Template

  test "template resource renders inline source with variable and assigns syntax" do
    template =
      Template.new("/etc/demo.conf",
        source: "name=<%= name %>\nhost=<%= @host %>\n",
        assigns: %{name: "demo", host: "demo.example.com"}
      )

    assert Template.render(template) == {:ok, "name=demo\nhost=demo.example.com\n"}
  end

  test "template assigns are normalized and may contain secret references" do
    template =
      Template.new("/etc/demo.conf",
        source: "token=<%= @token %>\n",
        assigns: [token: HostKit.Secret.env("APP_TOKEN"), port: 4000]
      )

    assert template.assigns == %{port: 4000, token: HostKit.Secret.env("APP_TOKEN")}
    assert Template.public_assigns(template) == %{"port" => 4000}
    assert Template.secret_assigns(template) == ["token"]
  end

  test "template redacted assigns are not renderable" do
    template =
      Template.new("/etc/demo.conf", source: "token=<%= @token %>\n", assigns: [token: :redacted])

    assert Template.render(template) == {:error, :redacted_secret_not_renderable}
  end

  test "template rendering resolves env-backed secret assigns" do
    System.put_env("HOSTKIT_TEMPLATE_TOKEN", "secret-value")

    template =
      Template.new("/etc/demo.conf",
        source: "token=<%= @token %>\n",
        assigns: %{token: HostKit.Secret.env("HOSTKIT_TEMPLATE_TOKEN")}
      )

    assert Template.render(template) == {:ok, "token=secret-value\n"}
  after
    System.delete_env("HOSTKIT_TEMPLATE_TOKEN")
  end

  test "template DSL resolves relative source paths from the declaring config" do
    config_dir = tmp_dir("template-dsl")
    File.mkdir_p!(Path.join(config_dir, "templates"))
    File.write!(Path.join(config_dir, "templates/app.conf.eex"), "port=<%= @port %>\n")

    config = Path.join(config_dir, "config.exs")

    File.write!(config, """
    use HostKit.DSL

    project :templates do
      template "/etc/app.conf", from: "templates/app.conf.eex", assigns: %{port: 4000}
    end
    """)

    project = HostKit.load!(config)

    assert [%Template{from: from} = template] = HostKit.Project.resources(project)
    assert from == Path.join(config_dir, "templates/app.conf.eex")
    assert Template.render(template) == {:ok, "port=4000\n"}
  after
    cleanup_tmp("template-dsl")
  end

  test "plan compares rendered template content with managed file on disk" do
    path = Path.join(tmp_dir("template-plan"), "app.conf")
    File.write!(path, "port=4000\n")

    project =
      project_with_template(path,
        source: "port=<%= @port %>\n",
        assigns: %{port: 4000}
      )

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%Change{action: :no_op, resource_id: {:template, ^path}}] = plan.changes

    drifted = project_with_template(path, source: "port=<%= @port %>\n", assigns: %{port: 5000})

    assert {:ok, plan} = HostKit.plan(drifted, reader: HostKit.Local)
    assert [%Change{action: :update, resource_id: {:template, ^path}} = change] = plan.changes
    assert HostKit.Plan.Format.format_change(change) =~ "assign changes:"
    assert HostKit.Plan.Format.format_change(change) =~ "~ port: :unknown -> 5000"
  after
    cleanup_tmp("template-plan")
  end

  test "secret-bearing templates produce redacted assign diffs without resolving secrets during plan" do
    path = Path.join(tmp_dir("template-secret-plan"), "app.conf")
    File.write!(path, "token=old\n")

    project =
      project_with_template(path,
        source: "token=<%= @token %>\nport=<%= @port %>\n",
        assigns: %{token: HostKit.Secret.env("HOSTKIT_TEMPLATE_MISSING_TOKEN"), port: 4000}
      )

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%Change{action: :update, resource_id: {:template, ^path}} = change] = plan.changes

    formatted = HostKit.Plan.Format.format_change(change)
    assert formatted =~ "assign changes:"
    assert formatted =~ "~ port: :unknown -> 4000"
    assert formatted =~ "redacted assigns: token"
    assert formatted =~ "rendered content: diff unavailable"
  after
    cleanup_tmp("template-secret-plan")
  end

  test "apply writes rendered template content" do
    path = Path.join(tmp_dir("template-apply"), "etc/app.conf")
    project = project_with_template(path, source: "name=<%= @name %>\n", assigns: %{name: "demo"})

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert {:ok, [%{status: :applied}]} = HostKit.apply(plan, confirm: true)

    assert File.read!(path) == "name=demo\n"
  after
    cleanup_tmp("template-apply")
  end

  defp project_with_template(path, opts) do
    %HostKit.Project{name: :templates}
    |> HostKit.Project.add_resource(Template.new(path, opts))
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
