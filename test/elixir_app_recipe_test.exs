defmodule HostKit.ElixirAppRecipeTest do
  use ExUnit.Case, async: true

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

    resources = HostKit.Project.resources(ElixirAppRecipeProject.project())

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
               inputs: [{:source, "hello_source"}, "mix.exs", "mix.lock"],
               outputs: ["deps"]
             } ->
               true

             _resource ->
               false
           end)

    assert Enum.any?(resources, &match?(%HostKit.Systemd.Service{name: "hello.service"}, &1))
    assert Enum.any?(resources, &match?(%HostKit.Caddy.Site{host: "hello.example.com"}, &1))
  end
end
