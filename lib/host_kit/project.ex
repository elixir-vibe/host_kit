defmodule HostKit.Project do
  @moduledoc "Project-level declaration loaded from HostKit DSL files."

  alias HostKit.{Conventions, Firewall, Provider, ProviderConfig, Proxy, Service, Tenant}
  alias HostKit.Resources.Mise

  @type t :: %__MODULE__{
          name: atom(),
          hosts: [HostKit.Host.t()],
          tenants: [Tenant.t()],
          services: [Service.t()],
          resources: [struct()],
          providers: [module()],
          provider_configs: %{optional(atom()) => ProviderConfig.t()},
          proxies: [Proxy.t()],
          conventions: map(),
          meta: map()
        }

  defstruct name: nil,
            hosts: [],
            tenants: [],
            services: [],
            resources: [],
            providers: [],
            provider_configs: %{},
            proxies: [],
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

  @spec fetch_host(t(), atom()) :: {:ok, HostKit.Host.t()} | :error
  def fetch_host(%__MODULE__{} = project, name) when is_atom(name) do
    case Enum.find(project.hosts, &(&1.name == name)) do
      nil -> :error
      host -> {:ok, host}
    end
  end

  @spec fetch_host(t(), String.t()) :: {:ok, HostKit.Host.t()} | :error
  def fetch_host(%__MODULE__{} = project, name) when is_binary(name) do
    fetch_host(project, String.to_existing_atom(name))
  rescue
    ArgumentError -> :error
  end

  @spec add_tenant(t(), Tenant.t()) :: t()
  def add_tenant(%__MODULE__{} = project, tenant),
    do: %{project | tenants: project.tenants ++ [tenant]}

  @spec add_service(t(), Service.t()) :: t()
  def add_service(%__MODULE__{} = project, service),
    do: %{project | services: project.services ++ [service]}

  @spec add_resource(t(), struct()) :: t()
  def add_resource(%__MODULE__{} = project, resource),
    do: %{project | resources: project.resources ++ [resource]}

  @spec add_proxy(t(), Proxy.t()) :: t()
  def add_proxy(%__MODULE__{} = project, %Proxy{} = proxy),
    do: %{project | proxies: project.proxies ++ [proxy]}

  @spec resources(t()) :: [struct()]
  def resources(%__MODULE__{} = project) do
    project.resources
    |> Kernel.++(project.proxies)
    |> Kernel.++(project.services |> Enum.flat_map(&expand_resources(&1.resources)))
    |> Kernel.++(Firewall.policies(project))
    |> Kernel.++(workspace_egress(project))
  end

  defp expand_resources(resources) do
    Enum.flat_map(resources, fn
      %Mise{} = mise -> Mise.package_resources(mise) ++ [mise]
      resource -> [resource]
    end)
  end

  defp workspace_egress(project) do
    project.services
    |> Enum.map(& &1.meta[:egress])
    |> Enum.reject(&is_nil/1)
  end
end
