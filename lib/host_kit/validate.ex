defmodule HostKit.Validate do
  @moduledoc "Validates resources through core validators and optional plugin validators."

  alias HostKit.{Project, Provider}

  @spec validate(Project.t(), struct(), map()) :: :ok | {:error, term()}
  def validate(%Project{} = project, resource, context \\ %{}) do
    case validate_core(resource, context) do
      :ignore -> Provider.validate(project.providers, resource, context)
      result -> result
    end
  end

  defp validate_core(%HostKit.Systemd.Service{} = service, _context),
    do: HostKit.Systemd.Service.validate(service)

  defp validate_core(%HostKit.Systemd.Timer{} = timer, _context),
    do: HostKit.Systemd.Timer.validate(timer)

  defp validate_core(_resource, _context), do: :ignore
end
