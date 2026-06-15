defmodule HostKit.Diff.Entry do
  @moduledoc "One structured diff entry for plan review."

  defstruct op: nil, path: [], before: nil, after: nil, sensitive: false

  @type op :: :add | :remove | :replace | :move | :copy | :test
  @type path :: [String.t() | integer()]
  @type t :: %__MODULE__{
          op: op(),
          path: path(),
          before: term(),
          after: term(),
          sensitive: boolean()
        }

  @spec render_path(t() | path()) :: String.t()
  def render_path(%__MODULE__{path: path}), do: render_path(path)
  def render_path([]), do: "<root>"

  def render_path([first | rest]) do
    [to_string(first) | Enum.map(rest, &render_segment/1)]
    |> IO.iodata_to_binary()
  end

  defp render_segment(index) when is_integer(index), do: ["[", Integer.to_string(index), "]"]
  defp render_segment(segment), do: [".", to_string(segment)]
end
