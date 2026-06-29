defmodule HostKit.Backup.Checksum do
  @moduledoc "Checksum helpers for HostKit backup archives."

  @spec write_sha256!(Path.t()) :: Path.t()
  def write_sha256!(path) do
    checksum_path = path <> ".sha256"

    hash =
      path
      |> File.stream!(64 * 1024, [])
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    File.write!(checksum_path, "#{hash}  #{Path.basename(path)}\n")
    File.chmod!(checksum_path, 0o600)
    checksum_path
  end
end
