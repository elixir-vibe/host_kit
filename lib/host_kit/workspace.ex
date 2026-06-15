defmodule HostKit.Workspace do
  @moduledoc "Helpers for workspace-scoped metadata."

  alias HostKit.{Conventions, Monitor, Project, Runtime}

  @spec exec(Project.t(), atom(), atom(), [String.t()], keyword()) ::
          {:ok, term()} | {:error, term()}
  def exec(%Project{} = project, owner, workspace, argv, opts \\ []) do
    case Keyword.get(opts, :via, :unitctl) do
      :agent -> exec_via_agent(project, owner, workspace, argv, opts)
      :unitctl -> exec_via_unitctl(project, owner, workspace, argv, opts)
    end
  end

  @spec exec_spec(Project.t(), atom(), atom(), [String.t()], keyword()) ::
          {:ok, Runtime.Spec.t()} | {:error, term()}
  def exec_spec(%Project{} = project, owner, workspace, argv, opts \\ []) do
    with {:ok, service} <-
           workspace_service(project, owner, workspace, Keyword.get(opts, :service, :agent)) do
      {:ok,
       Runtime.Spec.new!(
         name:
           Keyword.get(
             opts,
             :name,
             Enum.join([owner, workspace, System.unique_integer([:positive])], "-")
           ),
         command: argv,
         user: Keyword.get(opts, :user, service_user(service)),
         working_directory:
           Keyword.get(opts, :working_directory, workspace_dir(project, service)),
         sandbox: Keyword.get(opts, :sandbox, %{}),
         resources: Keyword.get(opts, :resources, %{})
       )}
    end
  end

  @spec run_inside_monitors(Project.t(), keyword()) ::
          {:ok, [Monitor.Result.t()]} | {:error, term()}
  def run_inside_monitors(%Project{} = project, opts \\ []) do
    project
    |> inside_monitors()
    |> Enum.group_by(& &1.workspace)
    |> Enum.reduce_while({:ok, []}, &run_workspace_inside_monitors(&1, &2, project, opts))
  end

  def start(project, owner, workspace, opts \\ []),
    do: lifecycle(:restart, project, owner, workspace, opts)

  def stop(project, owner, workspace, opts \\ []),
    do: lifecycle(:stop, project, owner, workspace, opts)

  def restart(project, owner, workspace, opts \\ []),
    do: lifecycle(:restart, project, owner, workspace, opts)

  def status(project, owner, workspace, opts \\ []) do
    with {:ok, service} <-
           workspace_service(project, owner, workspace, Keyword.get(opts, :service, :agent)) do
      HostKit.Runtime.status(unit_name(service), opts)
    end
  end

  @spec inside_monitors(Project.t()) :: [map()]
  def inside_monitors(%Project{} = project) do
    project.services
    |> Enum.flat_map(fn service ->
      service.meta
      |> Map.get(:inside_monitor, [])
      |> Enum.map(&%{workspace: service.meta[:workspace], service: service.name, check: &1})
    end)
  end

  defp lifecycle(action, project, owner, workspace, opts) do
    with {:ok, service} <-
           workspace_service(project, owner, workspace, Keyword.get(opts, :service, :agent)) do
      apply(HostKit.Runtime, action, [unit_name(service), opts])
    end
  end

  defp exec_via_unitctl(project, owner, workspace, argv, opts) do
    with {:ok, spec} <- exec_spec(project, owner, workspace, argv, opts) do
      Runtime.start(spec)
    end
  end

  defp exec_via_agent(project, owner, workspace, argv, opts) do
    with {:ok, service} <-
           workspace_service(project, owner, workspace, Keyword.get(opts, :service, :agent)),
         {:ok, socket} <- agent_socket(service) do
      workspace_agent_client(opts).exec(socket, argv, opts)
    end
  end

  defp run_workspace_inside_monitors({workspace, monitors}, {:ok, results}, project, opts) do
    checks = Enum.map(monitors, & &1.check)

    with {:ok, service} <-
           workspace_service(
             project,
             workspace.owner,
             workspace.name,
             Keyword.get(opts, :service, :agent)
           ),
         {:ok, socket} <- agent_socket(service),
         {:ok, workspace_results} <- workspace_agent_client(opts).run_checks(socket, checks, opts) do
      {:cont, {:ok, results ++ workspace_results}}
    else
      {:error, :workspace_service_not_found} ->
        pending = Enum.map(checks, &Monitor.Result.error(&1, :pending_workspace_agent))
        {:cont, {:ok, results ++ pending}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp workspace_service(project, owner, workspace, service_name) do
    Enum.find_value(project.services, {:error, :workspace_service_not_found}, fn service ->
      case service.meta[:workspace] do
        %{owner: ^owner, name: ^workspace} when service.name == service_name -> {:ok, service}
        _workspace -> nil
      end
    end)
  end

  defp workspace_agent_client(opts),
    do: Keyword.get(opts, :client, HostKit.Workspace.Agent.LocalClient)

  defp agent_socket(service) do
    case service.meta[:agent_socket] do
      nil -> {:error, :missing_workspace_agent_socket}
      socket -> {:ok, socket}
    end
  end

  defp unit_name(service), do: "hk-ws-#{service.identity}.service"
  defp service_user(service), do: service.identity && "hk-#{service.identity}"

  defp workspace_dir(project, service) do
    project.conventions
    |> Conventions.workspaces_root()
    |> Path.join(service.path)
  end
end
