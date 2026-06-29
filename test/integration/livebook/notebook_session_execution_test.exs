defmodule HostKit.Integration.Livebook.NotebookSessionExecutionTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 600_000

  @notebooks [
    "notebooks/learn/deploy_caddy_site.livemd",
    "notebooks/learn/deploy_phoenix_app.livemd"
  ]

  test "demo notebooks import and execute through a real Livebook session" do
    {output, status} =
      System.cmd(elixir!(), ["test/support/host_kit/livebook_session_runner.exs" | @notebooks],
        cd: File.cwd!(),
        env: env(),
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  defp elixir! do
    System.find_executable("elixir") || raise "could not find elixir executable"
  end

  defp env do
    home = System.fetch_env!("HOME")

    [
      {"MIX_HOME", Path.join(home, ".mix")},
      {"MIX_ARCHIVES", Path.join([home, ".mix", "archives"])},
      {"MIX_INSTALL_DIR", Path.join(System.tmp_dir!(), "hostkit-livebook-runner-mix-install")}
    ]
  end
end
