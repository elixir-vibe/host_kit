defmodule HostKit.Runtime do
  @moduledoc "Runtime controls for systemd-backed units and transient jobs."

  @type unit_ref :: Unitctl.Instance.t() | String.t()

  @doc "Starts a transient systemd service through Unitctl."
  @spec start(Unitctl.Spec.t() | keyword() | map()) ::
          {:ok, Unitctl.Instance.t()} | {:error, term()}
  defdelegate start(spec_or_attrs), to: Unitctl

  @doc "Stops a systemd unit or Unitctl instance."
  @spec stop(unit_ref(), keyword()) :: :ok | {:ok, Systemd.Job.t()} | {:error, term()}
  defdelegate stop(instance_or_unit, opts \\ []), to: Unitctl

  @doc "Restarts a systemd unit or Unitctl instance."
  @spec restart(unit_ref(), keyword()) :: :ok | {:ok, Systemd.Job.t()} | {:error, term()}
  defdelegate restart(instance_or_unit, opts \\ []), to: Unitctl

  @doc "Reads common systemd state for a unit or Unitctl instance."
  @spec inspect(unit_ref(), keyword()) :: {:ok, Systemd.UnitState.t()} | {:error, term()}
  defdelegate inspect(instance_or_unit, opts \\ []), to: Unitctl

  @doc "Reads runtime stats for a unit or Unitctl instance."
  @spec stats(unit_ref(), keyword()) :: {:ok, Unitctl.Stats.t()} | {:error, term()}
  defdelegate stats(instance_or_unit, opts \\ []), to: Unitctl
end
