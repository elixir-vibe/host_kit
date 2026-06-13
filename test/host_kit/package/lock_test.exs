defmodule HostKit.Package.LockTest do
  use ExUnit.Case, async: true

  alias HostKit.Package.Lock
  alias HostKit.Resources.Package

  defmodule FailingRepologyClient do
    def project(_project, _opts), do: flunk("resolver should use package lock")
    def project_by_package(_repo, _package, _opts), do: flunk("resolver should use package lock")
  end

  test "saves and loads package lock with json_codec" do
    path = Path.join(System.tmp_dir!(), "host-kit-package-lock-#{System.unique_integer()}.json")
    on_exit(fn -> File.rm(path) end)

    lock =
      %Lock{}
      |> Lock.put(:openssl_dev, "libssl-dev", "debian_13")
      |> Lock.put(:xsltproc, "xsltproc", "debian_13")

    assert :ok = Lock.save(path, lock)
    assert {:ok, loaded} = Lock.load(path)
    assert Lock.get(loaded, :openssl_dev, "debian_13") == {:ok, "libssl-dev"}
    assert Lock.get(loaded, :openssl_dev, "fedora_42") == :error
  end

  test "resolver uses package lock before Repology" do
    lock = Lock.put(%Lock{}, :openssl_dev, "libssl-dev", "debian_13")
    package = Package.new(:openssl_dev)

    assert {:ok, resolved} =
             HostKit.Package.Resolver.resolve(package,
               package_repo: "debian_13",
               package_lock: lock,
               repology_client: FailingRepologyClient
             )

    assert resolved.system_name == "libssl-dev"
  end
end
