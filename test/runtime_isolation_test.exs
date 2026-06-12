defmodule HostKit.RuntimeIsolationTest do
  use ExUnit.Case, async: true

  alias HostKit.Runtime.{Resources, Sandbox}

  test "builds reusable sandbox profiles" do
    sandbox = Sandbox.new(:strict_web)

    assert sandbox.no_new_privileges == true
    assert sandbox.protect_system == :strict
    assert sandbox.restrict_address_families == [:inet, :inet6, :unix]
  end

  test "converts sandbox to systemd service options" do
    opts =
      Sandbox.new(:web_service)
      |> Sandbox.to_systemd_service_options()

    assert opts[:no_new_privileges] == true
    assert opts[:private_tmp] == true
    assert opts[:protect_system] == :full
    assert opts[:restrict_address_families] == "AF_INET AF_INET6 AF_UNIX"
  end

  test "converts resource controls to systemd service options" do
    opts =
      Resources.new(:small)
      |> Resources.to_systemd_service_options()

    assert opts[:memory_max] == "512M"
    assert opts[:cpu_quota] == "50%"
    assert opts[:tasks_max] == 128
  end

  test "accepts explicit isolation attrs" do
    sandbox = Sandbox.new(no_new_privileges: true, read_write_paths: ["/srv/app"])
    resources = Resources.new(memory_max: "768M", cpu_weight: 200)

    assert sandbox.read_write_paths == ["/srv/app"]
    assert resources.cpu_weight == 200
  end
end
