defmodule HostKit.ConventionsTest do
  use ExUnit.Case, async: true

  alias HostKit.Conventions

  test "HostKit run tracking roots default under the state root" do
    conventions = Conventions.new()

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
