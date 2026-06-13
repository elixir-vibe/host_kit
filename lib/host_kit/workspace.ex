defmodule HostKit.Workspace do
  @moduledoc "Helpers for workspace-scoped metadata."

  alias HostKit.{Monitor, Project, Runtime}

  @spec exec(Project.t(), atom(), atom(), [String.t()], keyword()) ::
          {:ok, term()} | {:error, term()}
  def exec(%Project{} = project, owner, workspace, argv, opts \\ []) do
    with {:ok, spec} <- exec_spec(project, owner, workspace, argv, opts) do
      Runtime.start(spec)
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
         working_directory: Keyword.get(opts, :working_directory, workspace_dir(service)),
         sandbox: Keyword.get(opts, :sandbox, %{}),
         resources: Keyword.get(opts, :resources, %{})
       )}
    end
  end

  @spec run_inside_monitors(Project.t(), keyword()) :: {:ok, [Monitor.Result.t()]}
  def run_inside_monitors(%Project{} = project, _opts \\ []) do
    results =
      project
      |> inside_monitors()
      |> Enum.map(fn %{check: check} -> Monitor.Result.error(check, :pending_workspace_agent) end)

    {:ok, results}
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

  defp workspace_service(project, owner, workspace, service_name) do
    Enum.find_value(project.services, {:error, :workspace_service_not_found}, fn service ->
      case service.meta[:workspace] do
        %{owner: ^owner, name: ^workspace} when service.name == service_name -> {:ok, service}
        _workspace -> nil
      end
    end)
  end

  defp service_user(service), do: service.meta.identity_name && "hk-#{service.meta.identity_name}"

  defp workspace_dir(service),
    do: service.meta.path_name && "/var/lib/hostkit/workspaces/#{service.meta.path_name}"
end
