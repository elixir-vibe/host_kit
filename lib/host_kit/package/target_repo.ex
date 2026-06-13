defmodule HostKit.Package.TargetRepo do
  @moduledoc "Detects Repology repository names for package resolution targets."

  alias HostKit.Runner
  alias HostKit.Runner.Ops

  @spec detect(keyword()) :: {:ok, String.t()} | {:error, term()}
  def detect(opts) do
    case Runner.cmd(Ops.runner(opts), "sh", ["-c", os_release_command(opts)],
           stderr_to_stdout: true
         ) do
      {content, 0} -> content |> parse_os_release() |> repology_repo()
      {output, status} -> {:error, {:os_release_read_failed, status, output}}
    end
  end

  @spec parse_os_release(String.t()) :: map()
  def parse_os_release(content) do
    content
    |> String.split("\n")
    |> Enum.reduce(%{}, &parse_line/2)
  end

  @spec repology_repo(map()) :: {:ok, String.t()} | {:error, term()}
  def repology_repo(%{"ID" => "debian", "VERSION_ID" => version}),
    do: {:ok, "debian_#{normalize_version(version)}"}

  def repology_repo(%{"ID" => "ubuntu", "VERSION_ID" => version}),
    do: {:ok, "ubuntu_#{normalize_version(version)}"}

  def repology_repo(%{"ID" => "fedora", "VERSION_ID" => version}),
    do: {:ok, "fedora_#{normalize_version(version)}"}

  def repology_repo(%{"ID" => "alpine", "VERSION_ID" => version}),
    do: {:ok, "alpine_#{normalize_version(version)}"}

  def repology_repo(%{"ID" => "arch"}), do: {:ok, "arch"}

  def repology_repo(%{"ID" => id, "VERSION_ID" => version}),
    do: {:error, {:unsupported_os_release, id, version}}

  def repology_repo(%{"ID" => id}), do: {:error, {:unsupported_os_release, id, nil}}
  def repology_repo(_values), do: {:error, :invalid_os_release}

  defp parse_line(line, values) do
    case String.split(line, "=", parts: 2) do
      ["#" <> _comment, _value] -> values
      ["", _value] -> values
      [key, value] -> Map.put(values, key, unquote_value(value))
      _line -> values
    end
  end

  defp unquote_value(<<"\"", rest::binary>>) do
    rest |> String.trim_trailing("\"") |> String.replace(~s(\\"), ~s("))
  end

  defp unquote_value(value), do: value

  defp normalize_version(version), do: String.replace(version, ".", "_")

  defp os_release_command(opts) do
    prefix = if Keyword.get(opts, :sudo, false), do: "sudo ", else: ""
    "#{prefix}cat /etc/os-release"
  end
end
