defmodule HostKit.CommandLineTest do
  use ExUnit.Case, async: true

  alias HostKit.CommandLine

  test "builds GNU-style argv with positional args and options" do
    command =
      CommandLine.argv("mix",
        args: ["exograph.web"],
        opts: [
          backend: "duckdb",
          manifest_path: "/srv/manifest.json",
          verbose: true,
          dry_run: false
        ]
      )

    assert command.command == "mix"

    assert command.args == [
             "exograph.web",
             "--backend",
             "duckdb",
             "--manifest-path",
             "/srv/manifest.json",
             "--verbose"
           ]
  end

  test "supports alternate option styles" do
    assert %CommandLine{args: ["--foo-bar=baz"]} =
             CommandLine.argv("cmd", opts: [foo_bar: "baz"], style: :equals)

    assert %CommandLine{args: ["-foo-bar", "baz"]} =
             CommandLine.argv("cmd", opts: [foo_bar: "baz"], style: :single_dash)

    assert %CommandLine{args: ["-f", "baz", "-v"]} =
             CommandLine.argv("cmd", opts: [f: "baz", v: true], style: :short)

    assert %CommandLine{args: ["--foo_bar", "baz"]} =
             CommandLine.argv("cmd", opts: [foo_bar: "baz"], style: :underscore)
  end

  test "repeats list values" do
    assert %CommandLine{args: ["--include", "a", "--include", "b"]} =
             CommandLine.argv("cmd", opts: [include: ["a", "b"]])
  end
end
