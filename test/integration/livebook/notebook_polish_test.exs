defmodule HostKit.Integration.Livebook.NotebookPolishTest do
  use ExUnit.Case, async: true

  @notebooks [
    "notebooks/learn/deploy_caddy_site.livemd",
    "notebooks/learn/deploy_phoenix_app.livemd"
  ]

  test "demo notebooks use released HostKit and current Kino APIs" do
    for path <- @notebooks do
      content = File.read!(path)

      assert content =~ ~s({:host_kit, "== 0.1.0-beta.1"), path
      refute content =~ ~s(github: "elixir-vibe/host_kit"), path
      refute content =~ "Control.await", path
      refute content =~ "Kino.Control", path
      refute content =~ "Kino.Input", path
      refute content =~ "Kino.Markdown", path
      refute content =~ "System.get_env", path
    end
  end
end
