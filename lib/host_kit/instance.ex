defmodule HostKit.Instance do
  @moduledoc "Generic lifecycle-managed compute instance with nested HostKit contents."

  @type port_exposure :: %{
          name: atom(),
          host: non_neg_integer() | nil,
          guest: non_neg_integer(),
          protocol: :tcp | :udp
        }

  @type t :: %__MODULE__{
          name: atom(),
          backend: atom() | nil,
          image: String.t() | nil,
          kind: atom() | nil,
          lifecycle: atom(),
          ports: [port_exposure()],
          hosts: [HostKit.Host.t()],
          services: [HostKit.Service.t()],
          resources: [struct()],
          meta: map()
        }

  defstruct name: nil,
            backend: nil,
            image: nil,
            kind: nil,
            lifecycle: :persistent,
            ports: [],
            hosts: [],
            services: [],
            resources: [],
            meta: %{}

  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) when is_atom(name) do
    %__MODULE__{
      name: name,
      backend: Keyword.get(opts, :backend),
      image: Keyword.get(opts, :image),
      kind: Keyword.get(opts, :kind),
      lifecycle: Keyword.get(opts, :lifecycle, :persistent),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def id(%__MODULE__{name: name}), do: {:instance, name}

  def put_backend(%__MODULE__{} = instance, backend) when is_atom(backend),
    do: %{instance | backend: backend}

  def put_image(%__MODULE__{} = instance, image) when is_binary(image),
    do: %{instance | image: image}

  def put_kind(%__MODULE__{} = instance, kind) when is_atom(kind),
    do: %{instance | kind: kind}

  def put_lifecycle(%__MODULE__{} = instance, lifecycle) when is_atom(lifecycle),
    do: %{instance | lifecycle: lifecycle}

  def add_port(%__MODULE__{} = instance, name, opts) when is_atom(name) and is_list(opts) do
    port = %{
      name: name,
      host: Keyword.get(opts, :host),
      guest: Keyword.fetch!(opts, :guest),
      protocol: Keyword.get(opts, :protocol, :tcp)
    }

    %{instance | ports: instance.ports ++ [port]}
  end

  def add_host(%__MODULE__{} = instance, host),
    do: %{instance | hosts: instance.hosts ++ [host]}

  def add_service(%__MODULE__{} = instance, service),
    do: %{instance | services: instance.services ++ [service]}

  def add_resource(%__MODULE__{} = instance, resource),
    do: %{instance | resources: instance.resources ++ [resource]}
end
