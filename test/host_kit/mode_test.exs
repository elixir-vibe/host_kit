defmodule HostKit.ModeTest do
  use ExUnit.Case, async: true

  test "normalizes aliases" do
    assert HostKit.Mode.normalize!(:public_file) == 0o644
    assert HostKit.Mode.normalize!(:private_file) == 0o600
    assert HostKit.Mode.normalize!(:secret_group_file) == 0o640
    assert HostKit.Mode.normalize!(:private_dir) == 0o750
    assert HostKit.Mode.normalize!(:shared_dir) == 0o2775
  end

  test "normalizes tuple forms" do
    assert HostKit.Mode.normalize!({:rw, :r, nil}) == 0o640
    assert HostKit.Mode.normalize!({:rwx, :rx, :rx}) == 0o755
    assert HostKit.Mode.normalize!({:setgid, :rwx, :rwx, :rx}) == 0o2775
  end

  test "normalizes keyword forms" do
    assert HostKit.Mode.normalize!(owner: :rw, group: :r) == 0o640
    assert HostKit.Mode.normalize!(u: :rwx, g: :rx, o: :rx) == 0o755
    assert HostKit.Mode.normalize!(owner: [:read, :write], group: [:read], other: []) == 0o640

    assert HostKit.Mode.normalize!(owner: :rwx, group: :rwx, other: :rx, special: :setgid) ==
             0o2775
  end

  test "normalizes capability lists" do
    assert HostKit.Mode.normalize!([:owner_rw, :group_r]) == 0o640
    assert HostKit.Mode.normalize!([:owner_rwx, :group_rx, :other_rx]) == 0o755
    assert HostKit.Mode.normalize!([:setgid, :owner_rwx, :group_rwx, :other_rx]) == 0o2775
  end

  test "DSL resources normalize mode sugar" do
    source = """
    use HostKit.DSL

    project :demo do
      service :web do
        directory "/srv/app", mode: :private_dir
        file "/etc/app/env", mode: [owner: :rw, group: :r], content: :redacted
        env_file "/etc/app/dotenv", mode: {:rw, :r, nil} do
          set :MIX_ENV, :prod
        end
      end
    end
    """

    {%HostKit.Project{} = project, _binding} = Code.eval_string(source)
    assert [service] = project.services

    assert [
             %HostKit.Resources.Directory{mode: 0o750},
             %HostKit.Resources.File{mode: 0o640},
             %HostKit.Resources.EnvFile{mode: 0o640}
           ] = service.resources
  end

  test "invalid modes raise" do
    assert_raise ArgumentError, fn -> HostKit.Mode.normalize!(:wat) end
    assert_raise ArgumentError, fn -> HostKit.Mode.normalize!(owner: :dance) end
  end
end
