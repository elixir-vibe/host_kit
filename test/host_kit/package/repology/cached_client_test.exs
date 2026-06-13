defmodule HostKit.Package.Repology.CachedClientTest do
  use ExUnit.Case, async: true

  alias HostKit.Package.Repology.CachedClient
  alias HostKit.Package.Repology.Record

  defmodule CountingClient do
    def project(project, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:project, project})

      {:ok,
       [
         %Record{
           repo: "debian_13",
           srcname: to_string(project),
           binnames: ["#{project}-bin"],
           version: "1.0"
         }
       ]}
    end

    def project_by_package(repo, package, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:project_by_package, repo, package})

      {:ok,
       [
         %Record{
           repo: repo,
           srcname: package,
           binnames: [package],
           version: "1.0"
         }
       ]}
    end

    def projects(start, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:projects, start})
      {:ok, %{to_string(start || "first") => [%Record{repo: "debian_13", version: "1.0"}]}}
    end
  end

  defmodule FailingClient do
    def project(_project, _opts), do: {:error, {:http_error, 429, "slow down"}}
    def project_by_package(_repo, _package, _opts), do: {:error, {:http_error, 429, "slow down"}}
    def projects(_start, _opts), do: {:error, {:http_error, 429, "slow down"}}
  end

  test "serves fresh project responses from cache" do
    cache_dir = cache_dir()

    opts = [
      cache_dir: cache_dir,
      base_client: CountingClient,
      test_pid: self(),
      rate_limit: false
    ]

    assert {:ok, [%Record{srcname: "openssl"}]} = CachedClient.project(:openssl, opts)
    assert_received {:project, :openssl}

    assert {:ok, [%Record{srcname: "openssl"}]} =
             CachedClient.project(:openssl, Keyword.put(opts, :base_client, FailingClient))

    refute_received {:project, :openssl}
  end

  test "refreshes stale responses and falls back to stale cache on refresh errors" do
    cache_dir = cache_dir()

    opts = [
      cache_dir: cache_dir,
      cache_ttl: -1,
      base_client: CountingClient,
      test_pid: self(),
      rate_limit: false
    ]

    assert {:ok, [%Record{}]} = CachedClient.project(:curl, opts)
    assert_received {:project, :curl}

    assert {:ok, [%Record{srcname: "curl"}]} =
             CachedClient.project(:curl, Keyword.put(opts, :base_client, FailingClient))
  end

  test "does not cache project-by redirects when disabled" do
    cache_dir = cache_dir()

    opts = [
      cache: false,
      cache_dir: cache_dir,
      base_client: CountingClient,
      test_pid: self(),
      rate_limit: false
    ]

    assert {:ok, [%Record{srcname: "xsltproc"}]} =
             CachedClient.project_by_package("debian_13", "xsltproc", opts)

    assert {:ok, [%Record{srcname: "xsltproc"}]} =
             CachedClient.project_by_package("debian_13", "xsltproc", opts)

    assert_received {:project_by_package, "debian_13", "xsltproc"}
    assert_received {:project_by_package, "debian_13", "xsltproc"}
  end

  defp cache_dir do
    Path.join(System.tmp_dir!(), "host-kit-repology-cache-#{System.unique_integer([:positive])}")
  end
end
