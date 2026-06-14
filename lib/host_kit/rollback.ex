defmodule HostKit.Rollback do
  @moduledoc "Best-effort rollback for applied HostKit changes with captured previous state."

  alias HostKit.{Apply, Change, Plan}

  @supported [
    HostKit.Firewall,
    HostKit.Proxy,
    HostKit.Resources.Directory,
    HostKit.Resources.EnvFile,
    HostKit.Resources.File,
    HostKit.Systemd.Service,
    HostKit.Systemd.Timer
  ]

  @type result :: %{change: Change.t(), status: :rolled_back | :skipped}

  @spec run([Apply.result()], keyword()) :: {:ok, [result()]} | {:error, term()}
  def run(results, opts \\ []) when is_list(results) do
    {rollback_changes, skipped} = rollback_plan(results)

    case rollback_changes do
      [] ->
        {:ok, Enum.reverse(skipped)}

      changes ->
        plan = %Plan{project: %HostKit.Project{name: :rollback}, changes: changes, opts: opts}

        with {:ok, results} <- Apply.run(plan, Keyword.put(opts, :confirm, true)) do
          rolled_back = Enum.map(results, &%{change: &1.change, status: :rolled_back})
          {:ok, rolled_back ++ Enum.reverse(skipped)}
        end
    end
  end

  defp rollback_plan(results) do
    results
    |> Enum.reverse()
    |> Enum.reduce({[], []}, fn result, {changes, skipped} ->
      case rollback_change(result) do
        {:ok, change} ->
          {[change | changes], skipped}

        {:skip, reason, change} ->
          {changes, [%{change: change, status: :skipped, reason: reason} | skipped]}
      end
    end)
  end

  defp rollback_change(%{status: :applied, change: %Change{before: %module{} = before} = change})
       when module in @supported do
    {:ok,
     %Change{
       action: :update,
       resource_id: change.resource_id,
       before: change.after,
       after: before,
       reason: :rollback
     }}
  end

  defp rollback_change(%{status: :applied, change: %Change{before: nil} = change}) do
    {:skip, :no_previous_state, change}
  end

  defp rollback_change(%{status: :applied, change: %Change{} = change}) do
    {:skip, :unsupported_resource, change}
  end

  defp rollback_change(%{change: %Change{} = change}) do
    {:skip, :not_applied, change}
  end
end
