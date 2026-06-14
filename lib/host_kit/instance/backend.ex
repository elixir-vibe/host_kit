defmodule HostKit.Instance.Backend do
  @moduledoc "Backend behaviour for lifecycle-managed HostKit instances."

  alias HostKit.Instance

  @callback read(Instance.t(), keyword()) :: {:ok, Instance.t() | nil} | {:error, term()}
  @callback apply(Instance.t(), keyword()) :: :ok | {:error, term()}
  @callback delete(Instance.t(), keyword()) :: :ok | {:error, term()}

  @spec module(atom()) :: module()
  def module(:incus), do: HostKit.Instance.Backends.Incus
  def module(backend), do: raise(ArgumentError, "unknown instance backend: #{inspect(backend)}")

  @spec read(Instance.t(), keyword()) :: {:ok, Instance.t() | nil} | {:error, term()}
  def read(%Instance{backend: backend} = instance, opts) when is_atom(backend),
    do: module(backend).read(instance, opts)

  @spec apply(Instance.t(), keyword()) :: :ok | {:error, term()}
  def apply(%Instance{backend: backend} = instance, opts) when is_atom(backend),
    do: module(backend).apply(instance, opts)

  @spec delete(Instance.t(), keyword()) :: :ok | {:error, term()}
  def delete(%Instance{backend: backend} = instance, opts) when is_atom(backend),
    do: module(backend).delete(instance, opts)
end
