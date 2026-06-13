defmodule HostKit.Package do
  @moduledoc "Runtime boundary for reading and installing OS packages."

  alias HostKit.Resources.Package, as: PackageResource

  @callback read(PackageResource.t(), map()) ::
              {:ok, PackageResource.t() | nil} | {:error, term()}
  @callback install(PackageResource.t(), keyword()) :: :ok | {:error, term()}

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

  defp impl(%{opts: opts}), do: impl(opts)
  defp impl(opts) when is_list(opts), do: Keyword.get(opts, :package_impl, HostKit.Package.CLI)
  defp impl(_context), do: HostKit.Package.CLI
end
