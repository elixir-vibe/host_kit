defmodule HostKit.SigilsAndShellTest do
  use ExUnit.Case, async: true

  import HostKit.Sigils

  test "use HostKit imports DSL and sigils by default" do
    defmodule SigilProject do
      use HostKit, providers: [HostKit.Providers.Caddy], recipes: [HostKit.Recipes.ElixirApp]

      def project do
        project :sigils do
          service :demo do
            package(:wget)
            run(:download, ~SH"wget https://example.com/file")
          end
        end
      end
    end

    assert {:ok, plan} = HostKit.plan(SigilProject.project())

    assert Enum.any?(
             plan.resources,
             &match?(%HostKit.Resources.Command{exec: {"wget", ["https://example.com/file"]}}, &1)
           )
  end

  test "bash macro escapes interpolated values" do
    path = "/tmp/a path/with'quote"

    assert %HostKit.ShellScript{source: source} = bash("rm -rf #{path}")
    assert source == "rm -rf '/tmp/a path/with'\\''quote'"
  end

  test "~SH rejects shell features and points users to ~BASH" do
    assert_raise ArgumentError, ~r/redirections require ~BASH/, fn ->
      Code.eval_string(~S'''
      import HostKit.Sigils
      ~SH"echo hello > file"
      ''')
    end
  end

  test "bash resources analyze required commands" do
    defmodule BashProject do
      use HostKit

      def project do
        project :bash_missing do
          service :demo do
            bash(:fetch, ~BASH"""
            set -euo pipefail
            wget https://example.com/file -O file
            tar -xzf file
            """)
          end
        end
      end
    end

    assert {:error, %HostKit.Diagnostics{errors: errors}} = HostKit.plan(BashProject.project())
    commands = Enum.map(errors, & &1.details.command)
    assert "wget" in commands
    assert "tar" in commands
  end

  test "source locations are attached to missing command diagnostics" do
    defmodule SourceLocationProject do
      use HostKit

      def project do
        project :source_location do
          service :demo do
            run(:download, ~SH"wget https://example.com/file")
          end
        end
      end
    end

    assert {:error, %HostKit.Diagnostics{errors: [diagnostic]}} =
             HostKit.plan(SourceLocationProject.project())

    assert diagnostic.file =~ "sigils_and_shell_test.exs"
    assert is_integer(diagnostic.line)
  end
end
