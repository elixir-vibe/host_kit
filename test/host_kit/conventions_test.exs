defmodule HostKit.ConventionsTest do
  use ExUnit.Case, async: true

  alias HostKit.Conventions

  test "common executable roots and HostKit run tracking roots have defaults" do
    conventions = Conventions.new()

    assert Conventions.root!(conventions, :bin) == "/usr/local/bin"
    assert Conventions.root!(conventions, :sbin) == "/usr/local/sbin"
    assert Conventions.root(conventions, :bin, "/bin") == "/usr/local/bin"
    assert Conventions.state_root(conventions) == "/var/lib/hostkit"
    assert Conventions.runs_root(conventions) == "/var/lib/hostkit/runs"
    assert Conventions.backups_root(conventions) == "/var/lib/hostkit/backups"
  end

  test "HostKit run tracking roots follow configured project roots" do
    conventions = Conventions.new(roots: %{hostkit_state: "/srv/hostkit"})

    assert Conventions.state_root(conventions) == "/srv/hostkit"
    assert Conventions.runs_root(conventions) == "/srv/hostkit/runs"
    assert Conventions.backups_root(conventions) == "/srv/hostkit/backups"
  end

  test "workspace root can be configured independently" do
    assert Conventions.workspaces_root(Conventions.new()) == "/var/lib/hostkit/workspaces"

    assert Conventions.workspaces_root(Conventions.new(roots: %{data: "/srv/workspaces"})) ==
             "/srv/workspaces"

    assert Conventions.workspaces_root(
             Conventions.new(roots: %{data: "/srv/workspaces", workspaces: "/mnt/ws"})
           ) == "/mnt/ws"
  end

  test "specific run tracking roots can be overridden" do
    conventions =
      Conventions.new(
        roots: %{
          hostkit_state: "/srv/hostkit",
          hostkit_runs: "/run/hostkit/runs",
          hostkit_backups: "/backup/hostkit"
        }
      )

    assert Conventions.state_root(conventions) == "/srv/hostkit"
    assert Conventions.runs_root(conventions) == "/run/hostkit/runs"
    assert Conventions.backups_root(conventions) == "/backup/hostkit"
  end
end
