defmodule HostKit.Docs.ExecutableDSLSnippetsTest do
  use ExUnit.Case, async: true

  @docs [
    "README.md",
    "guides/introduction/getting-started.md",
    "guides/introduction/conventions-and-paths.md",
    "guides/deployment/remote-bootstrap.md",
    "guides/deployment/systemd-isolation.md",
    "guides/deployment/firewall-and-networking.md",
    "guides/operations/observability-and-monitors.md",
    "guides/workspaces/workspaces-and-tenants.md"
  ]

  test "canonical HostKit DSL snippets evaluate to projects" do
    snippets =
      @docs
      |> Enum.flat_map(&dsl_snippets/1)

    assert snippets != []

    for %{path: path, index: index, code: code} <- snippets do
      assert {%HostKit.Project{}, _binding} = Code.eval_string(code),
             "expected #{path} elixir snippet #{index} to evaluate to a HostKit project"
    end
  end

  defp dsl_snippets(path) do
    ~r/```elixir\n(.*?)\n```/s
    |> Regex.scan(File.read!(path), capture: :all_but_first)
    |> Enum.map(&List.first/1)
    |> Enum.with_index(1)
    |> Enum.filter(fn {code, _index} -> String.contains?(code, "use HostKit.DSL") end)
    |> Enum.map(fn {code, index} ->
      %{path: path, index: index, code: strip_file_comment(code)}
    end)
  end

  defp strip_file_comment("# " <> code) do
    code
    |> String.split("\n", parts: 2)
    |> case do
      [_comment, rest] -> rest
      [single] -> single
    end
  end

  defp strip_file_comment(code), do: code
end
