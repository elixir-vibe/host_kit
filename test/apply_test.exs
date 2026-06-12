defmodule HostKit.ApplyTest do
  use ExUnit.Case, async: true

  alias HostKit.Apply
  alias HostKit.Change
  alias HostKit.Plan
  alias HostKit.Resources.{Directory, File}

  test "requires confirmation outside dry-run" do
    plan = %Plan{changes: []}

    assert Apply.run(plan) == {:error, :confirmation_required}
  end

  test "dry-runs supported changes without touching filesystem" do
    path =
      Path.join(System.tmp_dir!(), "host-kit-apply-dry-run-#{System.unique_integer([:positive])}")

    plan = %Plan{
      changes: [
        %Change{
          action: :create,
          resource_id: {:directory, path},
          after: %Directory{path: path}
        }
      ]
    }

    assert {:ok, [%{status: :dry_run}]} = Apply.run(plan, dry_run: true)
    refute Elixir.File.exists?(path)
  end

  test "creates directories and files" do
    root = Path.join(System.tmp_dir!(), "host-kit-apply-#{System.unique_integer([:positive])}")
    dir = Path.join(root, "etc/app")
    file = Path.join(dir, "env")

    plan = %Plan{
      changes: [
        %Change{
          action: :create,
          resource_id: {:directory, dir},
          after: %Directory{path: dir, mode: 0o755}
        },
        %Change{
          action: :create,
          resource_id: {:file, file},
          after: %File{path: file, content: "PORT=4000\n", mode: 0o600}
        }
      ]
    }

    assert {:ok, [%{status: :applied}, %{status: :applied}]} = Apply.run(plan, confirm: true)
    assert Elixir.File.read!(file) == "PORT=4000\n"
    assert {:ok, %{mode: dir_mode}} = Elixir.File.stat(dir)
    assert {:ok, %{mode: file_mode}} = Elixir.File.stat(file)
    assert Bitwise.band(dir_mode, 0o777) == 0o755
    assert Bitwise.band(file_mode, 0o777) == 0o600

    Elixir.File.rm_rf!(root)
  end

  test "refuses to write redacted files" do
    plan = %Plan{
      changes: [
        %Change{
          action: :update,
          resource_id: {:file, "/tmp/redacted"},
          after: %File{path: "/tmp/redacted", content: :redacted}
        }
      ]
    }

    assert {:error, {{:file, "/tmp/redacted"}, :file_content_managed_elsewhere}} =
             Apply.run(plan, confirm: true)
  end
end
