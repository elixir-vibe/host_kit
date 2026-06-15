defmodule HostKit.Plan.ExecutionGraphTest do
  use ExUnit.Case, async: true

  alias HostKit.Addr.Resource
  alias HostKit.Change
  alias HostKit.Plan.ExecutionGraph
  alias HostKit.Readiness.Systemd
  alias HostKit.Resources.{Account, Command, Directory, File, Readiness, Source, Symlink}
  alias HostKit.Systemd.Service

  test "builds layers from parent directories and ownership" do
    account = %Account{name: "app"}
    directory = %Directory{path: "/srv/app", owner: "app"}
    file = %File{path: "/srv/app/config.env", owner: "app"}

    graph =
      graph_for([
        create({:account, "app"}, account),
        create({:directory, "/srv/app"}, directory),
        create({:file, "/srv/app/config.env"}, file)
      ])

    assert edge?(graph, {:account, "app"}, {:directory, "/srv/app"}, :owner_account)

    assert edge?(
             graph,
             {:directory, "/srv/app"},
             {:file, "/srv/app/config.env"},
             :parent_directory
           )

    assert ExecutionGraph.acyclic?(graph)

    assert graph.layers == [
             [{:account, "app"}],
             [{:directory, "/srv/app"}],
             [{:file, "/srv/app/config.env"}]
           ]
  end

  test "reverses derived edges for delete changes" do
    directory = %Directory{path: "/srv/app"}
    file = %File{path: "/srv/app/config.env"}

    graph =
      graph_for([
        delete({:file, "/srv/app/config.env"}, file),
        delete({:directory, "/srv/app"}, directory)
      ])

    assert edge?(
             graph,
             {:file, "/srv/app/config.env"},
             {:directory, "/srv/app"},
             :parent_directory
           )

    assert graph.layers == [[{:file, "/srv/app/config.env"}], [{:directory, "/srv/app"}]]
  end

  test "uses declared depends_on edges" do
    file = %File{path: "/etc/app.conf", depends_on: [{:package, :caddy}]}
    package = %HostKit.Resources.Package{name: :caddy}

    graph =
      graph_for([create({:file, "/etc/app.conf"}, file), create({:package, :caddy}, package)])

    assert edge?(graph, {:package, :caddy}, {:file, "/etc/app.conf"}, :explicit_dependency)
  end

  test "matches declared Addr.Resource dependencies against tuple resource ids" do
    file = %File{path: "/etc/app.conf", depends_on: [Resource.new(:package, :caddy)]}
    package = %HostKit.Resources.Package{name: :caddy}

    graph =
      graph_for([create({:file, "/etc/app.conf"}, file), create({:package, :caddy}, package)])

    assert edge?(graph, {:package, :caddy}, {:file, "/etc/app.conf"}, :explicit_dependency)
  end

  test "derives source input and systemd readiness edges" do
    source = %Source{name: :app, checkout: "/srv/app/source", uri: "https://example.test/app.git"}
    command = %Command{name: :build, exec: {"mix", ["compile"]}, inputs: [:app]}
    service = %Service{name: "app.service"}
    readiness = %Readiness{name: :app, checks: [%Systemd{unit: "app.service", state: :active}]}

    graph =
      graph_for([
        create({:source, :app}, source),
        create({:command, :build}, command),
        create({:systemd_service, "app.service"}, service),
        create({:readiness, :app}, readiness)
      ])

    assert edge?(graph, {:source, :app}, {:command, :build}, :source_input)

    assert edge?(
             graph,
             {:systemd_service, "app.service"},
             {:readiness, :app},
             :readiness_systemd
           )
  end

  test "reports cycles without hiding graph data" do
    one = %File{path: "/tmp/one", depends_on: [{:symlink, "/tmp/two"}]}
    two = %Symlink{path: "/tmp/two", to: "/tmp/one", depends_on: [{:file, "/tmp/one"}]}

    graph = graph_for([create({:file, "/tmp/one"}, one), create({:symlink, "/tmp/two"}, two)])

    refute ExecutionGraph.acyclic?(graph)
    assert graph.layers == []
    assert graph.cycles == [[{:file, "/tmp/one"}, {:symlink, "/tmp/two"}]]
  end

  test "formats a concise graph summary" do
    graph = graph_for([create({:directory, "/srv/app"}, %Directory{path: "/srv/app"})])

    assert ExecutionGraph.format(graph) ==
             """
             Execution graph: 1 nodes, 0 edges, 1 layers, 0 cycles

             Layer 1:
               create directory./srv/app
             """
             |> String.trim_trailing()
  end

  test "formats edge reasons" do
    graph =
      graph_for([
        create({:directory, "/srv/app"}, %Directory{path: "/srv/app"}),
        create({:file, "/srv/app/config.env"}, %File{path: "/srv/app/config.env"})
      ])

    assert ExecutionGraph.format(graph) ==
             """
             Execution graph: 2 nodes, 1 edges, 2 layers, 0 cycles

             Edges:
               directory./srv/app -> file./srv/app/config.env [parent_directory: /srv/app]

             Layer 1:
               create directory./srv/app

             Layer 2:
               create file./srv/app/config.env
             """
             |> String.trim_trailing()
  end

  test "returns JSON-safe graph data without raw structs" do
    graph =
      graph_for([
        create({:directory, "/srv/app"}, %Directory{path: "/srv/app"}),
        create({:file, "/srv/app/config.env"}, %File{path: "/srv/app/config.env"})
      ])

    json = ExecutionGraph.to_json(graph)

    assert Jason.encode!(json)
    assert get_in(json, ["stats", "nodes"]) == 2
    assert get_in(json, ["edges", Access.at(0), "reason"]) == "parent_directory"
    assert get_in(json, ["edges", Access.at(0), "from", "display"]) == "directory./srv/app"

    assert get_in(json, ["nodes", Access.at(0), "resource_type"]) ==
             "Elixir.HostKit.Resources.Directory"
  end

  defp graph_for(changes) do
    ExecutionGraph.build(%HostKit.Plan{changes: changes})
  end

  defp create(id, resource), do: %Change{action: :create, resource_id: id, after: resource}
  defp delete(id, resource), do: %Change{action: :delete, resource_id: id, before: resource}

  defp edge?(graph, from, to, reason) do
    Enum.any?(graph.edges, &(&1.from == from and &1.to == to and &1.reason == reason))
  end
end
