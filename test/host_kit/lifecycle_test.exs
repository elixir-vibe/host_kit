defmodule HostKit.LifecycleTest do
  use ExUnit.Case, async: true

  test "before_start emits a phased command and captures eval AST without executing it" do
    source = """
    use HostKit.DSL

    project :demo do
      service :app do
        before_start :migrate do
          eval Demo.ReleaseTasks.migrate()
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    [service] = project.services

    assert [
             %HostKit.Resources.Command{
               name: :migrate,
               phase: :before_start,
               exec: {"/usr/local/bin/elixir", ["-e", "Demo.ReleaseTasks.migrate()"]}
             }
           ] = service.resources
  end
end
