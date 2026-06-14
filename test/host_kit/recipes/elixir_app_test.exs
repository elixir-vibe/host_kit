defmodule HostKit.ElixirAppRecipeTest do
  use HostKit.Case, async: true

  test "elixir_app recipe expands to ordinary HostKit resources" do
    defmodule ElixirAppRecipeProject do
      use HostKit.DSL,
        providers: [HostKit.Providers.Caddy, HostKit.Providers.Elixir]

      def project do
        project :demo do
          elixir_app(:hello,
            source: [github: "elixir-vibe/host_kit", path: "examples/hello_phoenix", ref: "main"],
            runtime: [erlang: "27.2", elixir: "1.18.2-otp-27"],
            phoenix: [host: "hello.example.com", port: 4000, secret_key_base: "secret"],
            caddy: [host: "hello.example.com"]
          )
        end
      end
    end

    project = ElixirAppRecipeProject.project()
    resources = HostKit.Project.resources(project)

    assert [service] = project.services

    assert %HostKit.Endpoint{port: 4000, protocol: :http, health: "/health"} =
             service.meta.endpoints.http

    assert Enum.any?(resources, &match?(%HostKit.Resources.Package{name: :git}, &1))
    assert Enum.any?(resources, &match?(%HostKit.Resources.Package{name: :caddy}, &1))

    assert Enum.any?(resources, fn
             %HostKit.Resources.Mise{tools: tools} ->
               Enum.any?(tools, &(&1.name == :erlang and &1.version == "27.2")) and
                 Enum.any?(tools, &(&1.name == :elixir and &1.version == "1.18.2-otp-27"))

             _resource ->
               false
           end)

    assert Enum.any?(
             resources,
             &match?(%HostKit.Resources.EnvFile{path: "/etc/hostkit/hello.env"}, &1)
           )

    assert Enum.any?(resources, fn
             %HostKit.Resources.Source{
               name: "hello_source",
               uri: "https://github.com/elixir-vibe/host_kit.git",
               ref: "main",
               checkout: "/opt/hostkit/apps/hello/source",
               path: "examples/hello_phoenix"
             } ->
               true

             _resource ->
               false
           end)

    assert Enum.any?(resources, fn
             %HostKit.Resources.Command{
               name: "hello_deps",
               exec: {"mix", ["deps.get", "--only", "prod"]},
               runtime: {:mise, :beam},
               inputs: [%HostKit.Source.Ref{name: "hello_source"}, "mix.exs", "mix.lock"],
               outputs: ["deps"]
             } ->
               true

             _resource ->
               false
           end)

    assert Enum.any?(resources, fn
             %HostKit.Systemd.Service{name: "hello.service", service: service} ->
               service |> Keyword.get(:exec_start) |> List.wrap() |> hd() =~
                 "/_build/prod/rel/hello/bin/hello"

             _resource ->
               false
           end)

    assert Enum.any?(resources, fn
             %HostKit.Resources.Readiness{name: "hello_ready", checks: checks} ->
               match?(
                 [
                   %HostKit.Readiness.Systemd{unit: "hello.service", restart: true},
                   %HostKit.Readiness.HTTP{url: "http://127.0.0.1:4000/health", expect_body: "ok"}
                 ],
                 checks
               )

             _resource ->
               false
           end)

    assert Enum.any?(resources, &match?(%HostKit.Ingress{name: :hello}, &1))

    assert {:ok, plan} =
             HostKit.plan(project,
               package_repo: "ubuntu_24_04",
               package_lock: fixture_path("package_locks/beam_apt.package.lock")
             )

    assert Enum.any?(plan.resources, &match?(%HostKit.Caddy.Site{host: "hello.example.com"}, &1))
  end

  test "elixir_app block DSL expands to the same recipe options" do
    defmodule ElixirAppRecipeBlockProject do
      use HostKit.DSL,
        providers: [HostKit.Providers.Caddy, HostKit.Providers.Elixir]

      def project do
        project :demo do
          elixir_app :shop do
            source(github: "elixir-vibe/host_kit", path: "examples/hello_phoenix", ref: "main")
            phoenix(host: "shop.example.com", port: 4001, secret_key_base: "secret")

            ecto release: "Shop.Release" do
              repo("Shop.Repo")
              repo("Shop.AnalyticsRepo")
            end
          end
        end
      end
    end

    project = ElixirAppRecipeBlockProject.project()
    resources = HostKit.Project.resources(project)

    assert Enum.any?(resources, fn
             %HostKit.Resources.Command{name: "shop_ecto_migrate_repo", phase: :before_start} ->
               true

             _resource ->
               false
           end)

    assert Enum.any?(resources, fn
             %HostKit.Resources.Command{
               name: "shop_ecto_migrate_analytics_repo",
               phase: :before_start
             } ->
               true

             _resource ->
               false
           end)
  end

  test "elixir_app recipe emits reversible Ecto lifecycle command" do
    defmodule ElixirAppRecipeEctoProject do
      use HostKit.DSL,
        providers: [HostKit.Providers.Caddy, HostKit.Providers.Elixir]

      def project do
        project :demo do
          elixir_app(:shop,
            source: [github: "elixir-vibe/host_kit", path: "examples/hello_phoenix", ref: "main"],
            phoenix: [host: "shop.example.com", port: 4001, secret_key_base: "secret"],
            ecto: [release: "Shop.Release"]
          )
        end
      end
    end

    project = ElixirAppRecipeEctoProject.project()
    resources = HostKit.Project.resources(project)

    assert Enum.any?(resources, fn
             %HostKit.Resources.Command{
               name: "shop_ecto_migrate",
               exec: {"sh", ["-c", migrate]},
               down: %HostKit.Resources.Command{exec: {"sh", ["-c", rollback]}},
               phase: :before_start,
               depends_on: [{:command, "shop_release"}]
             } ->
               migrate =~ "Shop.Release.migrate()" and rollback =~ "Shop.Release.rollback()"

             _resource ->
               false
           end)

    assert {:ok, plan} =
             HostKit.plan(project,
               package_repo: "ubuntu_24_04",
               package_lock: fixture_path("package_locks/beam_apt.package.lock")
             )

    assert {:ok, down_plan} = HostKit.down(plan, only: [{:command, "shop_ecto_migrate"}])

    assert [
             %HostKit.Change{
               action: :create,
               resource_id: {:command, "shop_ecto_migrate_down"},
               after: %HostKit.Resources.Command{exec: {"sh", ["-c", rollback]}}
             }
           ] = down_plan.changes

    assert rollback =~ "Shop.Release.rollback()"
  end

  test "elixir_app recipe can emit Ecto lifecycle commands for multiple repos" do
    app =
      HostKit.Recipes.ElixirApp.assigns(:shop,
        source: [github: "elixir-vibe/host_kit", path: "examples/hello_phoenix", ref: "main"],
        phoenix: [host: "shop.example.com", port: 4001, secret_key_base: "secret"],
        ecto: [release: "Shop.Release", repos: ["Shop.Repo", "Shop.AnalyticsRepo"]]
      )

    assert Enum.map(app.ecto, & &1.name) == [
             "shop_ecto_migrate_repo",
             "shop_ecto_migrate_analytics_repo"
           ]

    assert Enum.map(app.ecto, & &1.migrate) == [
             "Shop.Release.migrate(Shop.Repo)",
             "Shop.Release.migrate(Shop.AnalyticsRepo)"
           ]

    assert Enum.map(app.ecto, & &1.rollback) == [
             "Shop.Release.rollback(Shop.Repo)",
             "Shop.Release.rollback(Shop.AnalyticsRepo)"
           ]
  end
end
