defmodule HostKit.LivebookNotebook do
  @moduledoc false

  @spec code_cell_containing!(Path.t(), String.t()) :: String.t()
  def code_cell_containing!(path, marker) do
    path
    |> File.read!()
    |> code_cells()
    |> Enum.find(&String.contains?(&1, marker))
    |> case do
      nil -> raise "could not find Livebook code cell containing #{inspect(marker)} in #{path}"
      source -> source
    end
  end

  defp code_cells(content) do
    {cells, current} =
      content
      |> String.split("\n")
      |> Enum.reduce({[], nil}, &collect_line/2)

    case current do
      nil -> Enum.reverse(cells)
      lines -> Enum.reverse([lines |> Enum.reverse() |> Enum.join("\n") | cells])
    end
  end

  defp collect_line("```elixir", {cells, nil}), do: {cells, []}

  defp collect_line("```", {cells, lines}) when is_list(lines) do
    {[lines |> Enum.reverse() |> Enum.join("\n") | cells], nil}
  end

  defp collect_line(line, {cells, lines}) when is_list(lines), do: {cells, [line | lines]}
  defp collect_line(_line, state), do: state
end
