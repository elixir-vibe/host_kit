defmodule HostKit.ResourceBuilderTest do
  use ExUnit.Case, async: true

  test "directory builder owns mode coercion" do
    directory = HostKit.Resources.Directory.new("/srv/app", owner: "app", mode: :private_dir)

    assert directory.path == "/srv/app"
    assert directory.owner == "app"
    assert directory.mode == 0o750
  end

  test "file builder owns mode coercion" do
    file =
      HostKit.Resources.File.new("/etc/app/env",
        content: :redacted,
        mode: [owner: :rw, group: :r]
      )

    assert file.content == :redacted
    assert file.mode == 0o640
  end

  test "env file builder owns mode coercion" do
    env_file = HostKit.Resources.EnvFile.new("/etc/app/env", mode: {:rw, :r, nil})

    assert env_file.mode == 0o640
  end
end
