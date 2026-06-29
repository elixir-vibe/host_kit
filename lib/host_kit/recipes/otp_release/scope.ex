defmodule HostKit.Recipes.OTPRelease.Scope do
  @moduledoc "Process-local ambient state for OTP release artifact collection."

  use DSL

  setting(:collect_release_kit?, default: false)
  setting(:release_kit_artifacts, default: [])

  def start_release_kit_collection do
    previous = current_release_kit_collection()

    put_collect_release_kit?(true)
    put_release_kit_artifacts([])

    previous
  end

  def current_release_kit_collection do
    %{
      collecting?: collect_release_kit?(),
      artifacts: release_kit_artifacts()
    }
  end

  def restore_release_kit_collection(%{collecting?: collecting?, artifacts: artifacts}) do
    put_collect_release_kit?(collecting?)
    put_release_kit_artifacts(artifacts)
  end

  def collecting_release_kit?, do: collect_release_kit?()

  def release_kit_artifacts_collected, do: release_kit_artifacts()

  def collect_release_kit_artifact(artifact) do
    put_release_kit_artifacts([artifact | release_kit_artifacts()])
  end
end
