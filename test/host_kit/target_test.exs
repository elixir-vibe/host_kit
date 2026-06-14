defmodule HostKit.TargetTest do
  use ExUnit.Case, async: true

  test "builds local targets" do
    target = HostKit.Target.local(:dev, sudo: true)

    assert target.name == :dev

    opts = HostKit.Target.opts(target, confirm: true)

    assert opts[:sudo] == true
    assert opts[:runner] == {HostKit.Runner.Local, sudo: true}
    assert opts[:confirm] == true
  end

  test "builds ssh targets" do
    target = HostKit.Target.ssh(:prod, host: "elixir.toys", user: "dannote", sudo: true)

    assert target.name == :prod

    opts = HostKit.Target.opts(target, dry_run: true)

    assert opts[:host] == "elixir.toys"
    assert opts[:user] == "dannote"
    assert opts[:sudo] == true
    assert opts[:runner] == {HostKit.Runner.SSH, host: "elixir.toys", user: "dannote", sudo: true}
    assert opts[:dry_run] == true
  end

  test "host DSL keeps ssh retry options with the target" do
    source = """
    use HostKit.DSL

    project :demo do
      host :prod do
        hostname "example.test"
        user "root"
        ssh retry: [attempts: 3, base_delay: 0], silently_accept_hosts: true
      end
    end
    """

    {%HostKit.Project{hosts: [host]}, _binding} = Code.eval_string(source)

    assert HostKit.Host.ssh_options(host)[:retry] == [attempts: 3, base_delay: 0]
  end

  test "top-level apply accepts targets" do
    target = HostKit.Target.local(:dev)
    plan = %HostKit.Plan{changes: []}

    assert HostKit.apply(plan, target: target, dry_run: true) == {:ok, []}
  end
end
