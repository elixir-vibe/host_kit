defmodule HostKit.WorkspaceSandboxTest do
  use ExUnit.Case, async: true

  test "sandbox applies workspace-friendly systemd isolation and resource limits" do
    source = """
    use HostKit.DSL

    project :demo do
      workspace :blog, owner: :alice do
        service :preview do
          daemon do
            exec ["mix", "phx.server"]
            isolate :vibe_dev do
            end
          end
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services
    assert [%HostKit.Systemd.Service{} = unit] = service.resources

    assert unit.service[:no_new_privileges] == true
    assert unit.service[:private_tmp] == true
    assert unit.service[:protect_system] == :full
    assert unit.service[:restrict_suid_sgid] == true
    assert unit.service[:restrict_address_families] == "AF_INET AF_INET6 AF_UNIX"
    assert unit.service[:memory_max] == "2G"
    assert unit.service[:cpu_quota] == "150%"
    assert unit.service[:tasks_max] == 512
    assert unit.meta.sandbox.profile == :vibe_dev
  end

  test "sandbox options override profile defaults" do
    source = """
    use HostKit.DSL

    project :demo do
      service :app do
        daemon unit_name() do
          exec ["/usr/bin/env", "true"]

          isolate :untrusted do
            memory_max "256M"
            private_network false
          end
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [%HostKit.Systemd.Service{} = unit] = HostKit.Project.resources(project)
    assert unit.service[:memory_max] == "256M"
    assert unit.service[:private_network] == false
    assert unit.meta.sandbox.profile == :untrusted
  end
end
