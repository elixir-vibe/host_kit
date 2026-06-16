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

  test "builds mix task command lines" do
    assert %CommandLine{command: "mix", args: ["ecto.migrate", "--quiet"]} =
             CommandLine.mix("ecto.migrate", opts: [quiet: true])

    assert %CommandLine{command: "mix", args: ["phx.server", "--port", "4000", "--", "tail"]} =
             CommandLine.mix(:"phx.server",
               opts: [port: 4000],
               trailing: ["--", "tail"]
             )

    assert %CommandLine{command: "/opt/mise/shims/mix", args: ["test"]} =
             CommandLine.mix("test", command: "/opt/mise/shims/mix")
  end

  test "builds elixir command lines" do
    assert %CommandLine{command: "elixir", args: ["--version"]} =
             CommandLine.elixir(args: ["--version"])

    assert %CommandLine{command: "elixir", args: ["script.exs", "--name", "demo"]} =
             CommandLine.elixir("script.exs", opts: [name: "demo"])

    assert %CommandLine{command: "/opt/mise/shims/elixir", args: ["--version"]} =
             CommandLine.elixir(command: "/opt/mise/shims/elixir", args: ["--version"])

    assert %CommandLine{command: "elixir", args: ["-e", "IO.puts(:ok)"]} =
             CommandLine.eval("IO.puts(:ok)")
  end

  test "supports trailing arguments after structured options" do
    assert %CommandLine{args: ["task", "--mode", "latest", "--no-bm25"]} =
             CommandLine.argv("mix",
               args: ["task"],
               opts: [mode: "latest"],
               trailing: ["--no-bm25"]
             )
  end
end
