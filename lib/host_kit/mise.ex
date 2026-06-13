defmodule HostKit.Mise do
  @moduledoc "Runtime boundary for managing mise and mise-installed tools."

  alias HostKit.Resources.Mise, as: MiseResource

  @callback read(MiseResource.t(), map()) :: {:ok, MiseResource.t() | nil} | {:error, term()}
  @callback install(MiseResource.t(), keyword()) :: :ok | {:error, term()}

  @spec read(MiseResource.t(), map()) :: {:ok, MiseResource.t() | nil} | {:error, term()}
  def read(%MiseResource{} = mise, context \\ %{}) do
    implementation = impl(context)
    implementation.read(mise, context)
  end

  @spec install(MiseResource.t(), keyword()) :: :ok | {:error, term()}
  def install(%MiseResource{} = mise, opts \\ []) do
    implementation = impl(opts)
    implementation.install(mise, opts)
  end

  defp impl(%{opts: opts}), do: impl(opts)
  defp impl(opts) when is_list(opts), do: Keyword.get(opts, :mise_impl, HostKit.Mise.CLI)
  defp impl(_context), do: HostKit.Mise.CLI
end
