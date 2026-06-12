defmodule HostKit.CaddyLocalPlanTest do
  use ExUnit.Case, async: false

  test "caddy provider config lets local planning compare rendered site files" do
    tmp = Path.join(System.tmp_dir!(), "host-kit-caddy-#{System.unique_integer([:positive])}")
    Elixir.File.mkdir_p!(tmp)
    on_exit(fn -> Elixir.File.rm_rf(tmp) end)

    Elixir.File.write!(Path.join(tmp, "exograph-search.caddy"), """
    search.elixir.toys {
    \tencode zstd gzip
    \treverse_proxy 127.0.0.1:4200
    }
    """)

    previous = System.get_env("HOST_KIT_CADDY_TEST_SITES_DIR")
    System.put_env("HOST_KIT_CADDY_TEST_SITES_DIR", tmp)
    on_exit(fn -> restore_env(previous) end)

    project = HostKit.load!(fixture_path("caddy_local_project.hostkit"))

    assert %{caddy: %HostKit.ProviderConfig{config: %{sites_dir: ^tmp}}} =
             project.provider_configs

    assert {:ok, plan} = HostKit.plan(project, reader: HostKit.Local)
    assert [%HostKit.Change{action: :no_op, reason: :in_sync}] = plan.changes
  end

  defp restore_env(nil), do: System.delete_env("HOST_KIT_CADDY_TEST_SITES_DIR")
  defp restore_env(value), do: System.put_env("HOST_KIT_CADDY_TEST_SITES_DIR", value)

  defp fixture_path(name), do: Path.expand("fixtures/#{name}", __DIR__)
end
