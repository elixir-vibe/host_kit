defmodule HostKit.Project do
  @moduledoc "Project-level declaration loaded from HostKit DSL files."

  alias HostKit.{
    Conventions,
    Firewall,
    Host,
    Instance,
    Provider,
    ProviderConfig,
    Proxy,
    Service,
    Tenant
  }

  alias HostKit.Resources.Mise

  @type t :: %__MODULE__{
          name: atom(),
          hosts: [HostKit.Host.t()],
          tenants: [Tenant.t()],
          services: [Service.t()],
          instances: [Instance.t()],
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
            instances: [],
            resources: [],
            providers: [],
            provider_configs: %{},
            proxies: [],
            conventions: %{},
            meta: %{}

  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) when is_atom(name) do
    providers = opts |> Keyword.get(:providers, []) |> Provider.resolve()

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

  @spec add_instance(t(), Instance.t()) :: t()
  def add_instance(%__MODULE__{} = project, %Instance{} = instance),
    do: %{project | instances: project.instances ++ [instance]}

  @spec fetch_instance(t(), atom() | String.t()) :: {:ok, Instance.t()} | :error
  def fetch_instance(%__MODULE__{} = project, name) when is_atom(name) do
    case Enum.find(project.instances, &(&1.name == name)) do
      nil -> :error
      instance -> {:ok, instance}
    end
  end

  def fetch_instance(%__MODULE__{} = project, name) when is_binary(name) do
    fetch_instance(project, String.to_existing_atom(name))
  rescue
    ArgumentError -> :error
  end

  @spec add_resource(t(), struct()) :: t()
  def add_resource(%__MODULE__{} = project, resource),
    do: %{project | resources: project.resources ++ [resource]}

  @spec add_proxy(t(), Proxy.t()) :: t()
  def add_proxy(%__MODULE__{} = project, %Proxy{} = proxy),
    do: %{project | proxies: project.proxies ++ [proxy]}

  @doc "Reads current target state for this project's desired resources."
  @spec read(t(), keyword()) :: {:ok, [struct() | nil]} | {:error, term()}
  def read(%__MODULE__{} = project, opts \\ []) do
    with {:ok, plan} <- audit(project, opts) do
      {:ok, Enum.map(plan.changes, & &1.before)}
    end
  end

  @doc "Audits this project by building a plan against the selected target."
  @spec audit(t(), keyword()) :: {:ok, HostKit.Plan.t()} | {:error, term()}
  def audit(%__MODULE__{} = project, opts \\ []) do
    HostKit.plan(project, opts)
  end

  @doc "Returns project resources, optionally scoped to selected services."
  @spec resources(t(), keyword()) :: [struct()]
  def resources(%__MODULE__{} = project, opts \\ []) do
    selected_services = selected_services!(project, opts)
    services = selected_services || project.services

    resources =
      if selected_services do
        services |> Enum.flat_map(&service_resources(project, &1))
      else
        project.resources
        |> Kernel.++(Enum.flat_map(project.instances, &instance_resources/1))
        |> Kernel.++(project.proxies)
        |> Kernel.++(services |> Enum.flat_map(&service_resources(project, &1)))
      end

    resources = HostKit.RPC.apply_permissions(project, resources)

    resources
    |> Kernel.++(
      HostKit.RPC.binding_resources(project, services: service_names(selected_services))
    )
    |> Kernel.++(if(selected_services, do: [], else: Firewall.policies(project)))
    |> Kernel.++(workspace_egress(project, selected_services))
  end

  @doc "Resolves service selectors against service name, identity, or path."
  @spec resolve_services(t(), [atom() | String.t()] | nil) ::
          {:ok, [atom()] | nil} | {:error, term()}
  def resolve_services(%__MODULE__{} = project, selectors) do
    case resolve_selected_services(project, selectors) do
      {:ok, services} -> {:ok, service_names(services)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Resolves service selectors or raises on unknown/ambiguous selectors."
  @spec resolve_services!(t(), [atom() | String.t()] | nil) :: [atom()] | nil
  def resolve_services!(%__MODULE__{} = project, selectors) do
    case resolve_services(project, selectors) do
      {:ok, services} -> services
      {:error, reason} -> raise ArgumentError, format_service_selection_error(reason)
    end
  end

  defp selected_services!(%__MODULE__{} = project, opts) do
    case resolve_selected_services(project, Keyword.get(opts, :services)) do
      {:ok, services} -> services
      {:error, reason} -> raise ArgumentError, format_service_selection_error(reason)
    end
  end

  defp resolve_selected_services(%__MODULE__{} = project, selectors) do
    case List.wrap(selectors) do
      [] ->
        {:ok, nil}

      selectors ->
        Enum.reduce_while(selectors, {:ok, []}, fn selector, {:ok, services} ->
          case resolve_service(project, selector) do
            {:ok, service} -> {:cont, {:ok, [service | services]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:ok, services} -> {:ok, services |> Enum.reverse() |> Enum.uniq_by(& &1.name)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp resolve_service(%__MODULE__{} = project, selector) do
    matches = Enum.filter(project.services, &service_matches?(&1, selector))

    case matches do
      [service] ->
        {:ok, service}

      [] ->
        {:error, {:unknown_service, selector}}

      services ->
        {:error, {:ambiguous_service, selector, Enum.map(services, & &1.name)}}
    end
  end

  defp format_service_selection_error({:unknown_service, selector}),
    do: "unknown HostKit service #{inspect(selector)}"

  defp format_service_selection_error({:ambiguous_service, selector, services}) do
    names = Enum.map_join(services, ", ", &inspect/1)
    "ambiguous HostKit service #{inspect(selector)} matches #{names}"
  end

  defp service_matches?(%Service{name: name}, selector) when is_atom(selector),
    do: name == selector

  defp service_matches?(%Service{} = service, selector) when is_binary(selector) do
    selector in [Atom.to_string(service.name), service.identity, service.path]
  end

  defp service_matches?(_service, _selector), do: false

  defp service_names(nil), do: nil
  defp service_names(services), do: Enum.map(services, & &1.name)

  defp instance_resources(%Instance{} = instance) do
    [instance | instance_content_resources(instance)]
  end

  defp instance_content_resources(%Instance{} = instance) do
    host = instance_target_host(instance)

    instance.resources
    |> Kernel.++(instance.services |> Enum.flat_map(&expand_resources(&1.resources)))
    |> Enum.map(&put_instance_target(&1, instance, host))
  end

  defp instance_target_host(%Instance{target_host: nil, hosts: hosts}), do: List.first(hosts)

  defp instance_target_host(%Instance{target_host: name, hosts: hosts}) do
    Enum.find(hosts, &(&1.name == name)) ||
      raise ArgumentError, "instance target_host #{inspect(name)} is not declared"
  end

  defp put_instance_target(resource, _instance, nil), do: resource

  defp put_instance_target(resource, instance, %Host{} = host) do
    put_meta(resource, %{
      instance: instance.name,
      host: host.name,
      target_opts: Host.target_opts(host)
    })
  end

  defp put_meta(resource, values) do
    if Map.has_key?(resource, :meta) do
      %{resource | meta: Map.merge(resource.meta, values)}
    else
      resource
    end
  end

  defp service_resources(project, service) do
    service.resources
    |> expand_resources()
    |> HostKit.RPC.apply_runtime_bindings(project, service)
  end

  defp expand_resources(resources) do
    Enum.flat_map(resources, fn
      %Mise{} = mise -> Mise.package_resources(mise) ++ [mise]
      resource -> [resource]
    end)
  end

  defp workspace_egress(project, nil), do: workspace_egress(project, project.services)

  defp workspace_egress(_project, services) do
    services
    |> Enum.map(& &1.meta[:egress])
    |> Enum.reject(&is_nil/1)
  end
end
