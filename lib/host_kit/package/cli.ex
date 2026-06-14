defmodule HostKit.Package.CLI do
  @moduledoc "Package runtime implementation backed by common OS package managers."

  @behaviour HostKit.Package

  alias HostKit.Package.Manager
  alias HostKit.Resources.Package, as: PackageResource
  alias HostKit.Runner.Ops

  @impl true
  def read(%PackageResource{} = package, context) do
    opts = Map.get(context, :opts, [])

    with {:ok, manager} <- manager(opts) do
      read_package(manager, package, opts)
    end
  end

  @impl true
  def install(%PackageResource{} = package, opts) do
    install_many([package], opts)
  end

  @impl true
  def install_many(packages, opts) do
    with {:ok, manager} <- manager(opts) do
      install_packages(manager, packages, opts)
    end
  end

  defp read_package(:apt, package, opts) do
    command =
      "dpkg-query -W -f='${db:Status-Status}\\t${Version}' #{HostKit.Shell.escape(package.system_name)}"

    case sh(opts, command) do
      {:ok, output} -> package_status(package, output)
      {:error, {_status, _output}} -> {:ok, nil}
    end
  end

  defp read_package(:dnf, package, opts) do
    command = "rpm -q --qf '%{VERSION}-%{RELEASE}' #{HostKit.Shell.escape(package.system_name)}"

    case sh(opts, command) do
      {:ok, output} -> {:ok, installed(package, String.trim(output))}
      {:error, {_status, _output}} -> {:ok, nil}
    end
  end

  defp read_package(:pacman, package, opts) do
    command = "pacman -Q #{HostKit.Shell.escape(package.system_name)}"

    case sh(opts, command) do
      {:ok, output} -> {:ok, installed(package, output |> String.trim() |> package_version())}
      {:error, {_status, _output}} -> {:ok, nil}
    end
  end

  defp read_package(:apk, package, opts) do
    command =
      "apk info -e #{HostKit.Shell.escape(package.system_name)} >/dev/null && apk info -v #{HostKit.Shell.escape(package.system_name)} | head -n 1"

    case sh(opts, command) do
      {:ok, output} -> {:ok, installed(package, output |> String.trim() |> apk_version(package))}
      {:error, {_status, _output}} -> {:ok, nil}
    end
  end

  defp install_packages(_manager, [], _opts), do: :ok

  defp install_packages(:apt, packages, opts) do
    update = if Enum.any?(packages, & &1.update), do: "apt-get update && ", else: ""

    sh_ok(
      opts,
      "DEBIAN_FRONTEND=noninteractive #{update}apt-get install -y -- #{package_specs(:apt, packages)}"
    )
  end

  defp install_packages(:dnf, packages, opts) do
    refresh = if Enum.any?(packages, & &1.update), do: " --refresh", else: ""
    sh_ok(opts, "dnf install -y#{refresh} -- #{package_specs(:dnf, packages)}")
  end

  defp install_packages(:pacman, packages, opts) do
    case pacman_package_summary(packages) do
      %{versioned: nil, update?: update?} ->
        refresh = if update?, do: "pacman -Sy && ", else: ""
        names = Enum.map_join(packages, " ", &HostKit.Shell.escape(&1.system_name))
        sh_ok(opts, "#{refresh}pacman -S --noconfirm --needed -- #{names}")

      %{versioned: package} ->
        {:error, {:version_pin_not_supported, :pacman, package.system_name}}
    end
  end

  defp install_packages(:apk, packages, opts) do
    update = if Enum.any?(packages, & &1.update), do: " --update-cache", else: ""
    sh_ok(opts, "apk add#{update} #{package_specs(:apk, packages)}")
  end

  defp pacman_package_summary(packages) do
    Enum.reduce(packages, %{versioned: nil, update?: false}, fn package, summary ->
      summary
      |> Map.update!(:update?, &(&1 or package.update))
      |> maybe_put_versioned_package(package)
    end)
  end

  defp maybe_put_versioned_package(%{versioned: nil} = summary, %{version: version} = package)
       when not is_nil(version),
       do: %{summary | versioned: package}

  defp maybe_put_versioned_package(summary, _package), do: summary

  defp manager(opts), do: Manager.resolve(opts)

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
    String.replace_prefix(line, package.system_name <> "-", "")
  end

  defp package_spec(:apt, %{system_name: system_name, version: nil}),
    do: HostKit.Shell.escape(system_name)

  defp package_spec(:apt, %{system_name: system_name, version: version}),
    do: HostKit.Shell.escape("#{system_name}=#{version}")

  defp package_spec(:dnf, %{system_name: system_name, version: nil}),
    do: HostKit.Shell.escape(system_name)

  defp package_spec(:dnf, %{system_name: system_name, version: version}),
    do: HostKit.Shell.escape("#{system_name}-#{version}")

  defp package_spec(:apk, %{system_name: system_name, version: nil}),
    do: HostKit.Shell.escape(system_name)

  defp package_spec(:apk, %{system_name: system_name, version: version}),
    do: HostKit.Shell.escape("#{system_name}=#{version}")

  defp package_specs(manager, packages) do
    packages
    |> Enum.uniq_by(&{&1.system_name, &1.version})
    |> Enum.map_join(" ", &package_spec(manager, &1))
  end

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
end
