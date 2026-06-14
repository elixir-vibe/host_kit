defmodule HostKit.Package do
  @moduledoc "Runtime boundary for reading and installing OS packages."

  alias HostKit.Resources.Package, as: PackageResource

  @callback read(PackageResource.t(), map()) ::
              {:ok, PackageResource.t() | nil} | {:error, term()}
  @callback install(PackageResource.t(), keyword()) :: :ok | {:error, term()}
  @callback install_many([PackageResource.t()], keyword()) :: :ok | {:error, term()}
  @optional_callbacks install_many: 2

  @spec read(PackageResource.t(), map()) :: {:ok, PackageResource.t() | nil} | {:error, term()}
  def read(%PackageResource{} = package, context \\ %{}) do
    implementation = impl(context)
    implementation.read(package, context)
  end

  @spec install(PackageResource.t(), keyword()) :: :ok | {:error, term()}
  def install(%PackageResource{} = package, opts \\ []) do
    implementation = impl(opts)
    implementation.install(package, opts)
  end

  @spec install_many([PackageResource.t()], keyword()) :: :ok | {:error, term()}
  def install_many(packages, opts \\ []) do
    implementation = impl(opts)

    Code.ensure_loaded?(implementation)

    install_many(implementation, packages, opts)
  end

  defp install_many(implementation, packages, opts) do
    if function_exported?(implementation, :install_many, 2) do
      implementation.install_many(packages, opts)
    else
      install_individually(implementation, packages, opts)
    end
  end

  defp install_individually(implementation, packages, opts) do
    Enum.reduce_while(packages, :ok, fn package, :ok ->
      case implementation.install(package, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp impl(%{opts: opts}), do: impl(opts)
  defp impl(opts) when is_list(opts), do: Keyword.get(opts, :package_impl, HostKit.Package.CLI)
  defp impl(_context), do: HostKit.Package.CLI
end
