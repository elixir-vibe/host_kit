defmodule HostKit.Instance do
  @moduledoc "Generic lifecycle-managed compute instance with nested HostKit contents."

  @type port_exposure :: %{
          name: atom(),
          host: non_neg_integer() | nil,
          guest: non_neg_integer(),
          protocol: :tcp | :udp,
          bind: String.t()
        }

  @type t :: %__MODULE__{
          name: atom(),
          backend: atom() | nil,
          backend_config: map(),
          image: String.t() | nil,
          kind: atom() | nil,
          lifecycle: atom(),
          ports: [port_exposure()],
          target_host: atom() | nil,
          hosts: [HostKit.Host.t()],
          services: [HostKit.Service.t()],
          resources: [struct()],
          meta: map()
        }

  defstruct name: nil,
            backend: nil,
            backend_config: %{},
            image: nil,
            kind: nil,
            lifecycle: :persistent,
            ports: [],
            target_host: nil,
            hosts: [],
            services: [],
            resources: [],
            meta: %{}

  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) when is_atom(name) do
    %__MODULE__{
      name: name,
      backend: Keyword.get(opts, :backend),
      backend_config: Map.new(Keyword.get(opts, :backend_config, [])),
      image: Keyword.get(opts, :image),
      kind: Keyword.get(opts, :kind),
      lifecycle: Keyword.get(opts, :lifecycle, :persistent),
      target_host: Keyword.get(opts, :target_host),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def id(%__MODULE__{name: name}), do: {:instance, name}

  def put_backend(%__MODULE__{} = instance, backend) when is_atom(backend),
    do: %{instance | backend: backend}

  def put_backend_config(%__MODULE__{} = instance, config) do
    %{instance | backend_config: Map.merge(instance.backend_config, Map.new(config))}
  end

  def put_image(%__MODULE__{} = instance, image) when is_binary(image),
    do: %{instance | image: image}

  def put_kind(%__MODULE__{} = instance, kind) when is_atom(kind),
    do: %{instance | kind: kind}

  def put_lifecycle(%__MODULE__{} = instance, lifecycle) when is_atom(lifecycle),
    do: %{instance | lifecycle: lifecycle}

  def put_target_host(%__MODULE__{} = instance, target_host) when is_atom(target_host),
    do: %{instance | target_host: target_host}

  def add_port(%__MODULE__{} = instance, name, opts) when is_atom(name) and is_list(opts) do
    port = %{
      name: name,
      host: Keyword.get(opts, :host),
      guest: Keyword.fetch!(opts, :guest),
      protocol: Keyword.get(opts, :protocol, :tcp),
      bind: Keyword.get(opts, :bind, "127.0.0.1")
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
