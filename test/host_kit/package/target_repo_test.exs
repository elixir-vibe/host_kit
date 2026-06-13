defmodule HostKit.Package.TargetRepoTest do
  use ExUnit.Case, async: true

  alias HostKit.Package.TargetRepo

  defmodule Runner do
    @behaviour HostKit.Runner

    def cmd("sh", ["-c", "cat /etc/os-release"], _opts) do
      {"ID=debian\nVERSION_ID=13\n", 0}
    end

    def mkdir_p(_path, _opts), do: :ok
    def write_file(_path, _content, _opts), do: :ok
  end

  test "parses os-release key values" do
    assert TargetRepo.parse_os_release(~s(ID=ubuntu\nVERSION_ID="24.04"\n)) == %{
             "ID" => "ubuntu",
             "VERSION_ID" => "24.04"
           }
  end

  test "maps os-release values to Repology repository names" do
    assert TargetRepo.repology_repo(%{"ID" => "debian", "VERSION_ID" => "13"}) ==
             {:ok, "debian_13"}

    assert TargetRepo.repology_repo(%{"ID" => "ubuntu", "VERSION_ID" => "24.04"}) ==
             {:ok, "ubuntu_24_04"}

    assert TargetRepo.repology_repo(%{"ID" => "alpine", "VERSION_ID" => "3.20"}) ==
             {:ok, "alpine_3_20"}
  end

  test "detects repository through runner" do
    assert TargetRepo.detect(runner: Runner) == {:ok, "debian_13"}
  end
end
