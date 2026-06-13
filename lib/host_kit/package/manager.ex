defmodule HostKit.Package.Manager do
  @moduledoc "Detects the target host package manager."

  alias HostKit.Runner.Ops

  @type t :: :apt | :dnf | :pacman | :apk

  @managers [apt: "apt-get", dnf: "dnf", pacman: "pacman", apk: "apk"]

  @spec resolve(keyword()) :: {:ok, t()} | {:error, term()}
  def resolve(opts) do
    case Keyword.get(opts, :package_manager) do
      manager when manager in [:apt, :dnf, :pacman, :apk] -> {:ok, manager}
      nil -> detect(opts)
      manager -> {:error, {:unsupported_package_manager, manager}}
    end
  end

  @spec detect(keyword()) :: {:ok, t()} | {:error, term()}
  def detect(opts) do
    Enum.find_value(@managers, fn {manager, command} ->
      if match?(:ok, Ops.cmd(opts, "sh", ["-c", "command -v #{command} >/dev/null 2>&1"])) do
        {:ok, manager}
      end
    end) || {:error, :package_manager_not_found}
  end
end
