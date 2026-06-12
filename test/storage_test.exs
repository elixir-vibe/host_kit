defmodule HostKit.StorageTest do
  use ExUnit.Case, async: true

  alias HostKit.Storage
  alias HostKit.Storage.Volume

  test "builds named storage volumes" do
    volume =
      Storage.volume(:repositories,
        path: "/srv/app/repositories",
        owner: "app",
        group: "app",
        mode: 0o750,
        backup: true
      )

    assert %Volume{} = volume
    assert volume.name == :repositories
    assert volume.writable == true
    assert volume.backup == true
  end

  test "converts volumes to directory resources" do
    volume =
      Storage.volume(:config,
        path: "/etc/app",
        owner: "root",
        group: "app",
        mode: 0o750,
        writable: false,
        secret: true
      )

    directory = Storage.directory(volume)

    assert directory.path == "/etc/app"
    assert directory.owner == "root"
    assert directory.group == "app"
    assert directory.mode == 0o750
    assert directory.meta.storage == :config
    assert directory.meta.secret == true
  end

  test "derives read-write paths" do
    data = Storage.volume(:data, path: "/srv/app", writable: true)
    config = Storage.volume(:config, path: "/etc/app", writable: false)

    assert Storage.read_write_path(data) == "/srv/app"
    assert Storage.read_write_path(config) == nil
    assert Storage.read_write_paths([data, config]) == ["/srv/app"]
  end

  test "uses mount path when provided" do
    volume = Storage.volume(:uploads, path: "/srv/app/uploads", mount_path: "/app/uploads")

    assert Storage.mount_path(volume) == "/app/uploads"
  end
end
