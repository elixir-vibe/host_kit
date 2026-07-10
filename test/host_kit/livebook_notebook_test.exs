defmodule HostKit.LivebookNotebookTest do
  use ExUnit.Case, async: true

  test "returns the code cell containing the marker" do
    path =
      temporary_notebook!("""
      # Demo

      ```elixir
      first = :cell
      ```

      ```elixir
      project :demo do
      end
      ```
      """)

    assert HostKit.LivebookNotebook.code_cell_containing!(path, "project :demo") ==
             "project :demo do\nend"
  end

  test "raises when no code cell contains the marker" do
    path = temporary_notebook!("```elixir\n:ok\n```\n")

    assert_raise RuntimeError, ~r/could not find Livebook code cell/, fn ->
      HostKit.LivebookNotebook.code_cell_containing!(path, "project :missing")
    end
  end

  defp temporary_notebook!(content) do
    path =
      Path.join(
        System.tmp_dir!(),
        "hostkit-livebook-notebook-#{System.unique_integer([:positive])}.livemd"
      )

    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
