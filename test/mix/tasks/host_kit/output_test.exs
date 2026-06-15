defmodule Mix.Tasks.HostKit.OutputTest do
  use ExUnit.Case, async: true

  alias HostKit.Change
  alias HostKit.Resources.Directory

  test "appends execution graph when requested" do
    plan = plan()

    output = Mix.Tasks.HostKit.Output.format_plan(plan, show_graph: true)

    assert output =~ "Plan: 1 to create"
    assert output =~ "Execution graph: 1 nodes, 0 edges, 1 layers, 0 cycles"
    assert output =~ "Layer 1:\n  create directory./srv/app"
  end

  test "appends JSON-safe execution graph when requested" do
    plan = plan()

    output = Mix.Tasks.HostKit.Output.format_plan(plan, show_graph: true, graph_format: "json")
    [_plan_text, graph_json] = String.split(output, "\n\n", parts: 2)
    decoded = Jason.decode!(graph_json)

    assert get_in(decoded, ["stats", "nodes"]) == 1
    assert get_in(decoded, ["nodes", Access.at(0), "display"]) == "directory./srv/app"
  end

  defp plan do
    %HostKit.Plan{
      changes: [
        %Change{
          action: :create,
          resource_id: {:directory, "/srv/app"},
          after: %Directory{path: "/srv/app"},
          reason: :missing
        }
      ]
    }
  end
end
