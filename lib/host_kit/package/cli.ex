defmodule HostKit.Package.CLI do
  @moduledoc "Package runtime implementation backed by common OS package managers."

  @behaviour HostKit.Package

  alias HostKit.Resources.Package, as: PackageResource
  alias HostKit.Runner.Ops

  @impl true
  def read(%PackageResource{} = package, context) do
    opts = Map.get(context, :opts, [])

    with {:ok, manager} <- manager(package, opts) do
      read_package(manager, package, opts)
    end
  end

  @impl true
  def install(%PackageResource{} = package, opts) do
    with {:ok, manager} <- manager(package, opts) do
      install_package(manager, package, opts)
    end
  end

  defp read_package(:apt, package, opts) do
    command =
      "dpkg-query -W -f='${db:Status-Status}\\t${Version}' #{shell_escape(package.package)}"

    case sh(opts, command) do
      {:ok, output} -> package_status(package, output)
      {:error, {_status, _output}} -> {:ok, nil}
    end
  end

  defp read_package(:dnf, package, opts) do
    command = "rpm -q --qf '%{VERSION}-%{RELEASE}' #{shell_escape(package.package)}"

    case sh(opts, command) do
      {:ok, output} -> {:ok, installed(package, String.trim(output))}
      {:error, {_status, _output}} -> {:ok, nil}
    end
  end

  defp read_package(:pacman, package, opts) do
    command = "pacman -Q #{shell_escape(package.package)}"

    case sh(opts, command) do
      {:ok, output} -> {:ok, installed(package, output |> String.trim() |> package_version())}
      {:error, {_status, _output}} -> {:ok, nil}
    end
  end

  defp read_package(:apk, package, opts) do
    command =
      "apk info -e #{shell_escape(package.package)} >/dev/null && apk info -v #{shell_escape(package.package)} | head -n 1"

    case sh(opts, command) do
      {:ok, output} -> {:ok, installed(package, output |> String.trim() |> apk_version(package))}
      {:error, {_status, _output}} -> {:ok, nil}
    end
  end

  defp install_package(:apt, package, opts) do
    update = if package.update, do: "apt-get update && ", else: ""

    sh_ok(
      opts,
      "DEBIAN_FRONTEND=noninteractive #{update}apt-get install -y -- #{package_spec(:apt, package)}"
    )
  end

  defp install_package(:dnf, package, opts) do
    refresh = if package.update, do: " --refresh", else: ""
    sh_ok(opts, "dnf install -y#{refresh} -- #{package_spec(:dnf, package)}")
  end

  defp install_package(:pacman, package, opts) do
    if package.version do
      {:error, {:version_pin_not_supported, :pacman, package.package}}
    else
      refresh = if package.update, do: "pacman -Sy && ", else: ""
      sh_ok(opts, "#{refresh}pacman -S --noconfirm --needed -- #{shell_escape(package.package)}")
    end
  end

  defp install_package(:apk, package, opts) do
    update = if package.update, do: " --update-cache", else: ""
    sh_ok(opts, "apk add#{update} #{package_spec(:apk, package)}")
  end

  defp manager(%PackageResource{manager: manager}, _opts)
       when manager in [:apt, :dnf, :pacman, :apk],
       do: {:ok, manager}

  defp manager(_package, opts) do
    case Keyword.get(opts, :package_manager) do
      manager when manager in [:apt, :dnf, :pacman, :apk] -> {:ok, manager}
      nil -> detect_manager(opts)
      manager -> {:error, {:unsupported_package_manager, manager}}
    end
  end

  defp detect_manager(opts) do
    Enum.find_value([apt: "apt-get", dnf: "dnf", pacman: "pacman", apk: "apk"], fn {manager,
                                                                                    command} ->
      if match?(:ok, Ops.cmd(opts, "sh", ["-c", "command -v #{command} >/dev/null 2>&1"])) do
        {:ok, manager}
      end
    end) || {:error, :package_manager_not_found}
  end

  defp package_status(package, output) do
    case String.split(output, "\t", parts: 2) do
      ["installed", version] -> {:ok, installed(package, version)}
      _fields -> {:ok, nil}
    end
  end

  defp installed(package, version) do
    %{package | meta: package.meta |> Map.put(:installed, true) |> Map.put(:version, version)}
  end

  defp package_version(line) do
    line
    |> String.split(" ", parts: 2)
    |> List.last()
  end

  defp apk_version("", _package), do: ""

  defp apk_version(line, package) do
    String.replace_prefix(line, package.package <> "-", "")
  end

  defp package_spec(:apt, %{package: package, version: nil}), do: shell_escape(package)

  defp package_spec(:apt, %{package: package, version: version}),
    do: shell_escape("#{package}=#{version}")

  defp package_spec(:dnf, %{package: package, version: nil}), do: shell_escape(package)

  defp package_spec(:dnf, %{package: package, version: version}),
    do: shell_escape("#{package}-#{version}")

  defp package_spec(:apk, %{package: package, version: nil}), do: shell_escape(package)

  defp package_spec(:apk, %{package: package, version: version}),
    do: shell_escape("#{package}=#{version}")

  defp sh_ok(opts, command) do
    case sh(opts, command) do
      {:ok, _output} ->
        :ok

      {:error, {status, output}} ->
        {:error, {:command_failed, "sh", ["-c", command], status, output}}
    end
  end

  defp sh(opts, command) do
    case HostKit.Runner.cmd(Ops.runner(opts), "sh", ["-c", command], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, status} -> {:error, {status, output}}
    end
  end

  defp shell_escape(value), do: "'" <> String.replace(to_string(value), "'", "'\\''") <> "'"
end
