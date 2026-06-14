defmodule HostKit.WorkspaceScopeTest do
  use ExUnit.Case, async: true

  test "workspace scopes regular services with metadata and path names" do
    source = """
    use HostKit.DSL

    project :demo do
      roots data: "/var/lib/hostkit/workspaces"
      prefixes user: "hk-", unit: "hk-ws-"

      workspace :blog, owner: :alice do
        service :preview do
          directory root_path(:data), mode: :private_dir

          daemon unit_name() do
            run exec_start: ["/usr/bin/env", "true"]
            listen :http, port: 4000, on: :loopback
          end
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services
    assert service.meta.workspace == %{name: :blog, owner: :alice}
    assert service.meta.path_name == "alice/blog/preview"
    assert service.meta.identity_name == "alice-blog-preview"

    assert [%HostKit.Resources.Directory{} = directory, %HostKit.Systemd.Service{} = unit] =
             service.resources

    assert directory.path == "/var/lib/hostkit/workspaces/alice/blog/preview"
    assert unit.name == "hk-ws-alice-blog-preview.service"
    assert service.meta.listeners.http.port == 4000
  end

  test "workspace path can be overridden" do
    source = """
    use HostKit.DSL

    project :demo do
      workspace :blog, owner: :alice, path: "custom/blog" do
        service :agent do
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services
    assert service.meta.path_name == "alice/custom/blog/agent"
    assert service.meta.identity_name == "alice-custom-blog-agent"
  end
end
