defmodule HostKit.Package.Repology.ClientTest do
  use ExUnit.Case, async: true

  alias HostKit.Package.Repology.Client
  alias HostKit.Package.Repology.Record

  test "decodes Repology project package records with json_codec" do
    adapter = fn request ->
      send(self(), {:request, request.method, request.url.path, request.headers})

      response =
        Req.Response.json([
          %{
            "repo" => "debian_13",
            "srcname" => "openssl",
            "binname" => "openssl",
            "binnames" => ["openssl", "libssl-dev"],
            "version" => "3.5.1",
            "status" => "newest"
          }
        ])

      {request, response}
    end

    assert {:ok, [%Record{} = record]} =
             Client.project(:openssl,
               base_url: "https://repology.test/api/v1",
               user_agent: "host-kit-test",
               req_options: [adapter: adapter]
             )

    assert record.repo == "debian_13"
    assert record.srcname == "openssl"
    assert record.binnames == ["openssl", "libssl-dev"]
    assert record.status == "newest"

    assert_received {:request, :get, "/api/v1/project/openssl", headers}
    assert headers["user-agent"] == ["host-kit-test"]
  end

  test "returns package names for matching repositories" do
    adapter = fn request ->
      response =
        Req.Response.json([
          %{
            "repo" => "debian_13",
            "binnames" => ["openssl", "libssl-dev"],
            "version" => "3.5.1"
          },
          %{
            "repo" => "fedora_rawhide",
            "binname" => "openssl-devel",
            "version" => "3.5.1"
          }
        ])

      {request, response}
    end

    assert {:ok, ["libssl-dev", "openssl"]} =
             Client.package_names(:openssl, ~r/^debian_/,
               base_url: "https://repology.test/api/v1",
               req_options: [adapter: adapter]
             )
  end

  test "returns http errors" do
    adapter = fn request -> {request, %Req.Response{status: 429, body: "slow down"}} end

    assert {:error, {:http_error, 429, "slow down"}} =
             Client.project(:openssl,
               base_url: "https://repology.test/api/v1",
               req_options: [adapter: adapter]
             )
  end
end
