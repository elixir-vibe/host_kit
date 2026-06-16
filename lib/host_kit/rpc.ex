defmodule HostKit.RPC do
  @moduledoc """
  Service-to-service RPC binding metadata.

  HostKit models the deployment wiring: which service exposes broad RPC surfaces
  and which other services are bound to them. Runtime protocols such as SafeRPC
  own exact operations, schemas, and handshakes.
  """

  alias HostKit.{Conventions, Diagnostic, Diagnostics, Listener, Project, Service}
  alias HostKit.Resources.File
  alias HostKit.RPC.{Binding, Exposure}

  @type t :: %__MODULE__{
          exposes: [Exposure.t()],
          bindings: [Binding.t()]
        }

  defstruct exposes: [], bindings: []

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      exposes: Keyword.get(opts, :exposes, []),
      bindings: Keyword.get(opts, :bindings, [])
    }
  end

  @spec add_exposure(t(), Exposure.t()) :: t()
  def add_exposure(%__MODULE__{} = rpc, %Exposure{} = exposure),
    do: %{rpc | exposes: rpc.exposes ++ [exposure]}

  @spec add_binding(t(), Binding.t()) :: t()
  def add_binding(%__MODULE__{} = rpc, %Binding{} = binding),
    do: %{rpc | bindings: rpc.bindings ++ [binding]}

  @spec validate(Project.t()) :: :ok | {:error, Diagnostics.t()}
  def validate(%Project{} = project) do
    diagnostics =
      project.services
      |> Enum.flat_map(&binding_diagnostics(project, &1))
      |> Diagnostics.new()

    if Diagnostics.ok?(diagnostics), do: :ok, else: {:error, diagnostics}
  end

  @spec apply_permissions(Project.t(), [struct()]) :: [struct()]
  def apply_permissions(%Project{} = project, resources) when is_list(resources) do
    caller_groups = caller_rpc_groups(project)

    Enum.map(resources, fn
      %HostKit.Resources.Account{name: name, groups: groups} = account ->
        extra_groups = Map.get(caller_groups, name, [])
        %{account | groups: Enum.uniq(groups ++ extra_groups)}

      resource ->
        resource
    end)
  end

  @spec binding_resources(Project.t()) :: [File.t()]
  def binding_resources(%Project{} = project) do
    service_index = service_index(project)

    project.services
    |> Enum.filter(&(rpc(&1).bindings != []))
    |> Enum.map(&binding_file(project, &1, service_index))
  end

  defp caller_rpc_groups(project) do
    service_index = service_index(project)

    project.services
    |> Enum.flat_map(fn caller ->
      caller_user = service_user(project, caller)

      caller
      |> rpc()
      |> Map.fetch!(:bindings)
      |> Enum.map(fn binding ->
        {caller_user, provider_group(project, service_index, binding)}
      end)
    end)
    |> Enum.reject(fn {_caller_user, group} -> is_nil(group) end)
    |> Enum.group_by(fn {caller_user, _group} -> caller_user end, fn {_caller_user, group} ->
      group
    end)
  end

  defp provider_group(project, service_index, %Binding{} = binding) do
    case Map.fetch(service_index, binding.service) do
      {:ok, provider} -> service_user(project, provider)
      :error -> nil
    end
  end

  defp binding_file(project, %Service{} = caller, service_index) do
    File.new(binding_path(project, caller),
      content: binding_content(project, caller, service_index),
      owner: "root",
      group: service_user(project, caller),
      mode: 0o640,
      meta: %{rpc_bindings_for: caller.name}
    )
  end

  defp binding_content(project, caller, service_index) do
    caller
    |> bindings_map(project, service_index)
    |> inspect(pretty: true, limit: :infinity, printable_limit: :infinity, width: 100)
    |> Kernel.<>("\n")
  end

  defp bindings_map(caller, project, service_index) do
    caller
    |> rpc()
    |> Map.fetch!(:bindings)
    |> Map.new(fn %Binding{} = binding ->
      provider = Map.fetch!(service_index, binding.service)
      surfaces = bound_surfaces(provider, binding)
      listener = provider.meta.listeners[binding.listener]

      {binding.service,
       %{
         listener: binding.listener,
         socket: listener.socket,
         upstream: Listener.upstream(listener),
         surfaces: surfaces,
         unit: unit_name(project, provider)
       }}
    end)
  end

  defp binding_path(project, service) do
    Path.join([
      Conventions.root(conventions(project), :config, "/etc"),
      service.path,
      "rpc.exs"
    ])
  end

  defp binding_diagnostics(project, %Service{} = caller) do
    service_index = service_index(project)

    caller
    |> rpc()
    |> Map.fetch!(:bindings)
    |> Enum.flat_map(&binding_diagnostics(caller, &1, service_index))
  end

  defp binding_diagnostics(%Service{} = caller, %Binding{} = binding, service_index) do
    cond do
      binding.service == caller.name ->
        [diagnostic(:rpc_self_binding, "service #{inspect(caller.name)} cannot bind itself")]

      not Map.has_key?(service_index, binding.service) ->
        [
          diagnostic(
            :rpc_unknown_service,
            "service #{inspect(caller.name)} binds unknown RPC service #{inspect(binding.service)}"
          )
        ]

      true ->
        provider = Map.fetch!(service_index, binding.service)
        provider_binding_diagnostics(caller, provider, binding)
    end
  end

  defp provider_binding_diagnostics(caller, provider, binding) do
    cond do
      not Map.has_key?(provider.meta[:listeners] || %{}, binding.listener) ->
        [
          diagnostic(
            :rpc_unknown_listener,
            "service #{inspect(caller.name)} binds #{inspect(provider.name)}.#{inspect(binding.listener)}, but that listener is not declared"
          )
        ]

      exposed_surfaces(provider, binding.listener) == [] ->
        [
          diagnostic(
            :rpc_no_surfaces,
            "service #{inspect(provider.name)} does not expose RPC surfaces on listener #{inspect(binding.listener)}"
          )
        ]

      missing = missing_surfaces(provider, binding) ->
        [
          diagnostic(
            :rpc_unknown_surface,
            "service #{inspect(caller.name)} binds unknown RPC surface(s) #{inspect(missing)} from #{inspect(provider.name)}"
          )
        ]

      true ->
        []
    end
  end

  defp missing_surfaces(_provider, %Binding{surfaces: []}), do: nil

  defp missing_surfaces(provider, %Binding{surfaces: surfaces, listener: listener}) do
    exposed = MapSet.new(exposed_surfaces(provider, listener))
    missing = Enum.reject(surfaces, &MapSet.member?(exposed, &1))
    if missing == [], do: nil, else: missing
  end

  defp bound_surfaces(provider, %Binding{surfaces: [], listener: listener}),
    do: exposed_surfaces(provider, listener)

  defp bound_surfaces(_provider, %Binding{surfaces: surfaces}), do: surfaces

  defp exposed_surfaces(provider, listener) do
    provider
    |> rpc()
    |> Map.fetch!(:exposes)
    |> Enum.filter(&(&1.listener == listener))
    |> Enum.map(& &1.name)
  end

  defp service_index(project), do: Map.new(project.services, &{&1.name, &1})

  defp rpc(%Service{} = service), do: Map.get(service.meta, :rpc, new())

  defp service_user(project, service),
    do: project |> conventions() |> Conventions.prefixed(:user, service.identity)

  defp unit_name(project, service),
    do:
      project
      |> conventions()
      |> Conventions.prefixed(:unit, service.identity)
      |> HostKit.Naming.systemd_unit()

  defp conventions(project), do: Conventions.new(project.conventions)

  defp diagnostic(code, message) do
    %Diagnostic{severity: :error, code: code, message: message}
  end
end
