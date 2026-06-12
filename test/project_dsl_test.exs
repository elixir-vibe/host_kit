defmodule HostKit.ProjectDSLTest do
  use ExUnit.Case, async: true

  test "project-local DSLs can define service conventions" do
    project = HostKit.load!(fixture_path("project_dsl.hostkit"))

    assert [service] = project.services
    assert service.name == :exograph

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Resources.User{name: "toys-exograph"}, &1)
           )

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Resources.Directory{path: "/srv/toys/exograph"}, &1)
           )

    assert Enum.any?(
             service.resources,
             &match?(%HostKit.Resources.Directory{path: "/var/lib/toys/exograph/home"}, &1)
           )

    assert Enum.any?(service.resources, fn
             %HostKit.Systemd.Service{name: "toys-exograph.service", service: service_opts} ->
               Keyword.fetch!(service_opts, :working_directory) == "/opt/toys/src/exograph" and
                 Keyword.fetch!(service_opts, :read_write_paths) == [
                   "/srv/toys/exograph",
                   "/var/lib/toys/exograph",
                   "/opt/toys/src/exograph"
                 ]

             _resource ->
               false
           end)
  end

  test "service names do not leak between services" do
    Code.compile_string("""
    defmodule HostKit.ProjectDSLServiceLeakFixture do
      use HostKit.ProjectDSL

      root :state, "/var/lib/apps"
      prefix :user, "app-"

      defservice :app_service do
        let :service_user, do: prefixed(:user, service_name())
        path :state_dir, root(:state), service_name()
      end
    end
    """)

    source = """
    use HostKit.DSL
    use HostKit.ProjectDSLServiceLeakFixture

    project :demo do
      app_service :alpha do
        directory state_path(), owner: service_user()
      end

      app_service :beta do
        directory state_path(), owner: service_user()
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)

    assert Enum.map(project.services, & &1.name) == [:alpha, :beta]

    assert [alpha, beta] = Enum.flat_map(project.services, & &1.resources)
    assert alpha.path == "/var/lib/apps/alpha"
    assert alpha.owner == "app-alpha"
    assert beta.path == "/var/lib/apps/beta"
    assert beta.owner == "app-beta"
  end

  test "unknown defservice entries raise helpful errors" do
    source = """
    defmodule HostKit.ProjectDSLBadEntryFixture do
      use HostKit.ProjectDSL

      defservice :bad do
        nope :thing
      end
    end
    """

    assert_raise HostKit.ProjectDSL.UnknownDefinitionError,
                 ~r/Supported forms inside defservice/,
                 fn ->
                   Code.compile_string(source)
                 end
  end

  test "unknown roots and prefixes raise helpful errors" do
    missing_root = """
    defmodule HostKit.ProjectDSLMissingRootFixture do
      use HostKit.ProjectDSL

      defservice :bad do
        path :state_dir, root(:state), service_name()
      end
    end
    """

    assert_raise HostKit.ProjectDSL.UnknownRootError, ~r/unknown ProjectDSL root :state/, fn ->
      Code.compile_string(missing_root)
    end

    missing_prefix = """
    defmodule HostKit.ProjectDSLMissingPrefixFixture do
      use HostKit.ProjectDSL

      defservice :bad do
        let :service_user, do: prefixed(:user, service_name())
      end
    end
    """

    assert_raise HostKit.ProjectDSL.UnknownPrefixError, ~r/unknown ProjectDSL prefix :user/, fn ->
      Code.compile_string(missing_prefix)
    end
  end

  defp fixture_path(name), do: Path.expand("fixtures/#{name}", __DIR__)
end
