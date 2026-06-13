defmodule HostKit.Package.ResolverTest do
  use ExUnit.Case, async: true

  alias HostKit.Package.Repology.Record
  alias HostKit.Package.Resolver
  alias HostKit.Resources.Package

  defmodule RepologyClient do
    def project("openssl", _opts) do
      {:ok,
       [
         %Record{
           repo: "debian_13",
           srcname: "openssl",
           binnames: ["openssl", "libssl-dev"],
           version: "3.5.1"
         },
         %Record{
           repo: "fedora_rawhide",
           srcname: "openssl",
           binnames: ["openssl", "openssl-devel"],
           version: "3.5.1"
         }
       ]}
    end

    def project("gcc", _opts) do
      {:ok,
       [
         %Record{repo: "fedora_rawhide", srcname: "gcc", binnames: ["gcc", "gcc-c++"]},
         %Record{repo: "debian_13", srcname: "gcc", binnames: ["gcc", "g++"]}
       ]}
    end
  end

  test "resolves semantic package capabilities through Repology" do
    package = Package.new(:openssl_dev, manager: :apt)

    assert {:ok, resolved} =
             Resolver.resolve(package,
               package_manager: :apt,
               repology_client: RepologyClient
             )

    assert resolved.package == "libssl-dev"
    assert resolved.source == :semantic
    assert resolved.meta.resolution.source == :repology
    assert resolved.meta.resolution.project == "openssl"
    assert resolved.meta.resolution.repo == "debian_13"
  end

  test "explicit package names are not resolved" do
    package = Package.new(:openssl_dev, package: "custom-openssl-dev")

    assert {:ok, ^package} =
             Resolver.resolve(package,
               package_manager: :apt,
               repology_client: RepologyClient
             )
  end

  test "manager selects repository family when exact repo is not provided" do
    package = Package.new(:cxx_compiler, manager: :dnf)

    assert {:ok, resolved} =
             Resolver.resolve(package,
               package_manager: :dnf,
               repology_client: RepologyClient
             )

    assert resolved.package == "gcc-c++"
  end

  test "planning resolves package resources before reading actual state" do
    package = Package.new(:openssl_dev, manager: :apt)

    project = %HostKit.Project{
      name: :demo,
      services: [%HostKit.Service{name: :bootstrap, resources: [package]}]
    }

    assert {:ok, plan} =
             HostKit.plan(project,
               package_manager: :apt,
               repology_client: RepologyClient
             )

    assert [%HostKit.Change{after: %Package{package: "libssl-dev"}}] = plan.changes
  end
end
