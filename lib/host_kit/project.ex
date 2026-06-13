defmodule HostKit.Project do
  @moduledoc "Project-level declaration loaded from HostKit DSL files."

  alias HostKit.{Conventions, Firewall, Provider, ProviderConfig, Service}

  @type t :: %__MODULE__{
          name: atom(),
          hosts: [HostKit.Host.t()],
          services: [Service.t()],
          providers: [module()],
          provider_configs: %{optional(atom()) => ProviderConfig.t()},
          conventions: map(),
          meta: map()
        }

  defstruct name: nil,
            hosts: [],
            services: [],
            providers: [],
            provider_configs: %{},
            conventions: %{},
            meta: %{}

  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) when is_atom(name) do
    providers =
      opts |> Keyword.get(:providers, Keyword.get(opts, :plugins, [])) |> Provider.resolve()

    %__MODULE__{
      name: name,
      providers: providers,
      conventions: opts |> Keyword.get(:conventions, %{}) |> Conventions.new(),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @spec put_providers(t(), [module()]) :: t()
  def put_providers(%__MODULE__{} = project, providers),
    do: %{project | providers: Provider.resolve(providers)}

  @spec put_convention_root(t(), atom(), String.t()) :: t()
  def put_convention_root(%__MODULE__{} = project, name, path) do
    %{
      project
      | conventions: Conventions.put_root(Conventions.new(project.conventions), name, path)
    }
  end

  @spec put_convention_prefix(t(), atom(), String.t()) :: t()
  def put_convention_prefix(%__MODULE__{} = project, name, prefix) do
    %{
      project
      | conventions: Conventions.put_prefix(Conventions.new(project.conventions), name, prefix)
    }
  end

  @spec put_provider_config(t(), ProviderConfig.t()) :: t()
  def put_provider_config(%__MODULE__{} = project, %ProviderConfig{} = config) do
    providers = Provider.resolve([config.module | project.providers])
    configs = Map.put(project.provider_configs, config.name, config)
    %{project | providers: providers, provider_configs: configs}
  end

  @spec add_host(t(), HostKit.Host.t()) :: t()
  def add_host(%__MODULE__{} = project, host), do: %{project | hosts: project.hosts ++ [host]}

  @spec add_service(t(), Service.t()) :: t()
  def add_service(%__MODULE__{} = project, service),
    do: %{project | services: project.services ++ [service]}

  @spec resources(t()) :: [struct()]
  def resources(%__MODULE__{} = project) do
    project.services
    |> Enum.flat_map(& &1.resources)
    |> Kernel.++(Firewall.policies(project))
  end
end
