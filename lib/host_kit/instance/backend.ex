defmodule HostKit.Instance.Backend do
  @moduledoc """
  Backend behaviour for lifecycle-managed HostKit instances.

  A backend owns the compute boundary lifecycle for an `HostKit.Instance`.
  HostKit keeps the user DSL generic (`instance`, `backend`, `image`, `kind`,
  `lifecycle`, `expose`) and delegates backend-specific lifecycle operations to
  this behaviour.

  Callback responsibilities:

  * `read/2` inspects whether the declared instance exists and returns the
    observed instance or `nil`.
  * `apply/2` makes the instance available for nested content application. For a
    VM/container backend this usually means create if missing, configure exposed
    ports, start, and wait until the instance can accept operations.
  * `delete/2` destroys the instance when a down plan includes an ephemeral
    instance delete.

  Backend options are stored on `HostKit.Instance.backend_config` by the DSL:

      instance :demo do
        backend :incus, sudo: true, project: "hostkit"
      end

      instance :staging do
        backend :libvirt, disk: "/var/lib/libvirt/images/staging.qcow2", memory_mb: 4096
      end

  Backends should emit `%HostKit.Apply.Event{}` progress through HostKit's
  apply event emitter when applying long-running lifecycle operations.
  """

  alias HostKit.Instance

  @callback read(Instance.t(), keyword()) :: {:ok, Instance.t() | nil} | {:error, term()}
  @callback apply(Instance.t(), keyword()) :: :ok | {:error, term()}
  @callback delete(Instance.t(), keyword()) :: :ok | {:error, term()}

  @spec module(atom()) :: module()
  def module(:incus), do: HostKit.Instance.Backends.Incus
  def module(:libvirt), do: HostKit.Instance.Backends.Libvirt
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
