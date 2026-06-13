defmodule HostKit.Package.Repology.Records do
  @moduledoc false

  alias HostKit.Package.Repology.Record

  @spec package_names([Record.t()], String.t() | Regex.t()) :: [String.t()]
  def package_names(records, repo_match) do
    records
    |> Enum.filter(&repo_match?(&1.repo, repo_match))
    |> Enum.flat_map(&record_package_names/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp record_package_names(%Record{binnames: names}) when names != [], do: names
  defp record_package_names(%Record{binname: name}) when is_binary(name), do: [name]
  defp record_package_names(%Record{srcname: name}) when is_binary(name), do: [name]
  defp record_package_names(_record), do: []

  defp repo_match?(repo, %Regex{} = regex), do: Regex.match?(regex, repo)
  defp repo_match?(repo, match) when is_binary(match), do: repo == match
end
