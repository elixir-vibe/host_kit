defmodule HostKit.Project do
  @moduledoc "Project-level declaration loaded from HostKit DSL files."

  alias HostKit.{Plugin, Service}

  @type t :: %__MODULE__{
          name: atom(),
          hosts: [HostKit.Host.t()],
          services: [Service.t()],
          plugins: [module()],
          conventions: map(),
          meta: map()
        }

  defstruct name: nil,
            hosts: [],
            services: [],
            plugins: [],
            conventions: %{},
            meta: %{}

  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) when is_atom(name) do
    plugins = opts |> Keyword.get(:plugins, []) |> Plugin.resolve()

    %__MODULE__{
      name: name,
      plugins: plugins,
      conventions: Keyword.get(opts, :conventions, %{}),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @spec put_plugins(t(), [module()]) :: t()
  def put_plugins(%__MODULE__{} = project, plugins),
    do: %{project | plugins: Plugin.resolve(plugins)}

  @spec add_host(t(), HostKit.Host.t()) :: t()
  def add_host(%__MODULE__{} = project, host), do: %{project | hosts: project.hosts ++ [host]}

  @spec add_service(t(), Service.t()) :: t()
  def add_service(%__MODULE__{} = project, service),
    do: %{project | services: project.services ++ [service]}

  @spec resources(t()) :: [struct()]
  def resources(%__MODULE__{} = project) do
    Enum.flat_map(project.services, & &1.resources)
  end
end
