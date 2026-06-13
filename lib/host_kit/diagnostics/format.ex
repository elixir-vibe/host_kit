defmodule HostKit.Diagnostics.Format do
  @moduledoc "Compiler-style rendering for HostKit diagnostics."

  alias HostKit.{Diagnostic, Diagnostics}

  @spec format(Diagnostics.t() | [Diagnostic.t()] | Diagnostic.t()) :: String.t()
  def format(%Diagnostics{} = diagnostics), do: diagnostics |> Diagnostics.all() |> format()

  def format(%Diagnostic{} = diagnostic), do: format([diagnostic])

  def format(diagnostics) when is_list(diagnostics) do
    diagnostics
    |> Enum.map(&format_diagnostic/1)
    |> Enum.intersperse("\n")
    |> IO.iodata_to_binary()
    |> String.trim_trailing()
  end

  defp format_diagnostic(%Diagnostic{} = diagnostic) do
    [
      Atom.to_string(diagnostic.severity),
      ": ",
      diagnostic.message,
      "\n",
      details(diagnostic),
      hint(diagnostic),
      location(diagnostic)
    ]
  end

  defp details(%Diagnostic{details: details}) when details == %{}, do: []

  defp details(%Diagnostic{details: details}) do
    Enum.map(details, fn {key, value} -> ["  ", to_string(key), ": ", inspect(value), "\n"] end)
  end

  defp hint(%Diagnostic{hint: nil}), do: []
  defp hint(%Diagnostic{hint: hint}), do: ["  hint: ", hint, "\n"]

  defp location(%Diagnostic{file: nil}), do: []

  defp location(%Diagnostic{} = diagnostic) do
    [
      "  └─ ",
      diagnostic.file,
      ":",
      to_string(diagnostic.line || 1),
      ":",
      to_string(diagnostic.column || 1),
      "\n"
    ]
  end
end
