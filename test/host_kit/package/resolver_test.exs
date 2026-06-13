defmodule HostKit.Package.ResolverTest do
  use ExUnit.Case, async: true

  alias HostKit.Package.Repology.Record
  alias HostKit.Package.Resolver
  alias HostKit.Resources.{Capability, Package}

  defmodule OsReleaseRunner do
    @behaviour HostKit.Runner

    def cmd("sh", ["-c", "cat /etc/os-release"], _opts), do: {"ID=debian\nVERSION_ID=13\n", 0}

    def mkdir_p(_path, _opts), do: :ok
    def write_file(_path, _content, _opts), do: :ok
  end

  defmodule RepologyClient do
    def project("openssl", _opts), do: openssl_records()
    def project(_package, _opts), do: {:error, {:http_error, 404, "missing"}}

    def project_by_package(_repo, package, _opts) when package in ["g++", "gcc-c++"],
      do: gcc_records()

    def project_by_package("fedora_42", "xsltproc", _opts),
      do: {:error, {:http_error, 404, "missing"}}

    def project_by_package("debian_13", "xsltproc", _opts), do: libxslt_records()

    defp openssl_records do
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

    defp gcc_records do
      {:ok,
       [
         %Record{repo: "fedora_rawhide", srcname: "gcc", binnames: ["gcc", "gcc-c++"]},
         %Record{repo: "debian_13", srcname: "gcc", binnames: ["gcc", "g++"]}
       ]}
    end

    defp libxslt_records do
      {:ok,
       [
         %Record{
           repo: "debian_13",
           srcname: "libxslt",
           binnames: ["libxslt1.1", "libxslt1-dev", "xsltproc"]
         },
         %Record{
           repo: "fedora_42",
           srcname: "libxslt",
           visiblename: "libxslt",
           binnames: ["libxslt", "libxslt-devel", "python3-libxslt"]
         }
       ]}
    end
  end

  test "resolves semantic package capabilities through Repology" do
    package = Package.new(:openssl_dev)

    assert {:ok, resolved} =
             Resolver.resolve(package,
               package_manager: :apt,
               repology_client: RepologyClient
             )

    assert resolved.system_name == "libssl-dev"
    assert resolved.source == :semantic
    assert resolved.meta.resolution.source == :repology
    assert resolved.meta.resolution.project == "openssl"
    assert resolved.meta.resolution.repo == "debian_13"
  end

  test "explicit package names are not resolved" do
    package = Package.new(:openssl_dev, as: "custom-openssl-dev")

    assert {:ok, ^package} =
             Resolver.resolve(package,
               package_manager: :apt,
               repology_client: RepologyClient
             )
  end

  test "detects exact target repository when manager and repo are not provided" do
    package = Package.new(:openssl_dev)

    assert {:ok, resolved} =
             Resolver.resolve(package,
               runner: OsReleaseRunner,
               repology_client: RepologyClient
             )

    assert resolved.system_name == "libssl-dev"
    assert resolved.meta.resolution.repo == "debian_13"
  end

  test "capability resources resolve through candidate package names" do
    capability = Capability.new(:cxx_compiler, candidates: ["g++", "gcc-c++"])

    assert {:ok, resolved} =
             Resolver.resolve(capability,
               package_manager: :dnf,
               repology_client: RepologyClient
             )

    assert resolved.system_name == "gcc-c++"
  end

  test "discovers Repology project by repository package name redirect" do
    package = Package.new(:xsltproc)

    assert {:ok, resolved} =
             Resolver.resolve(package,
               package_repo: "fedora_42",
               repology_client: RepologyClient
             )

    assert resolved.system_name == "libxslt"
    assert resolved.meta.resolution.project == "libxslt"
    assert resolved.meta.resolution.repo == "fedora_42"
  end

  test "planning resolves package resources before reading actual state" do
    package = Package.new(:openssl_dev)

    project = %HostKit.Project{
      name: :demo,
      services: [%HostKit.Service{name: :bootstrap, resources: [package]}]
    }

    assert {:ok, plan} =
             HostKit.plan(project,
               package_manager: :apt,
               repology_client: RepologyClient
             )

    assert [%HostKit.Change{after: %Package{system_name: "libssl-dev"}}] = plan.changes
  end
end
