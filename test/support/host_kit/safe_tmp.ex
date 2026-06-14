defmodule HostKit.SafeTmp do
  @moduledoc false

  def rm_rf!(path, prefix) when is_binary(path) and is_binary(prefix) do
    expanded = Path.expand(path)
    tmp = Path.expand(System.tmp_dir!())
    basename = Path.basename(expanded)

    unless String.starts_with?(expanded, tmp <> "/") and String.starts_with?(basename, prefix) do
      raise ArgumentError, "refusing to remove unsafe temporary path: #{expanded}"
    end

    File.rm_rf!(expanded)
  end
end
