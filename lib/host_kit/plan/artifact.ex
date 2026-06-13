defmodule HostKit.Plan.Artifact do
  @moduledoc "Portable JSON artifact for a resolved HostKit plan."

  use JSONCodec, fast_path: :json

  alias HostKit.{Change, Plan, Resource}

  @version 1

  defstruct version: @version,
            target: nil,
            project: nil,
            resources: [],
            changes: [],
            summary: %{}

  @type t :: %__MODULE__{
          version: pos_integer(),
          target: String.t() | nil,
          project: term(),
          resources: [term()],
          changes: [term()],
          summary: term()
        }

  codec(:version, transform: :validate_version!)

  @spec from_plan(Plan.t(), keyword()) :: t()
  def from_plan(%Plan{} = plan, opts \\ []) do
    %__MODULE__{
      target: Keyword.get(opts, :target),
      project: Resource.dump(plan.project),
      resources: Resource.dump(plan.resources),
      changes: Enum.map(plan.changes, &dump_change/1),
      summary: Resource.dump(plan.summary)
    }
  end

  @spec to_plan(t()) :: {:ok, Plan.t()} | {:error, term()}
  def to_plan(%__MODULE__{} = artifact) do
    {:ok,
     %Plan{
       project: Resource.load(artifact.project),
       resources: Resource.load(artifact.resources),
       changes: Enum.map(artifact.changes, &load_change/1),
       summary: Resource.load(artifact.summary),
       opts: []
     }}
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  @spec load(Path.t()) :: {:ok, Plan.t()} | {:error, term()}
  def load(path) do
    with {:ok, content} <- File.read(path),
         {:ok, artifact} <- decode(content) do
      to_plan(artifact)
    end
  end

  @spec save(Path.t(), Plan.t(), keyword()) :: :ok | {:error, term()}
  def save(path, %Plan{} = plan, opts \\ []) do
    content = plan |> from_plan(opts) |> dump() |> Jason.encode_to_iodata!(pretty: true)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, [content, ?\n])
    end
  end

  def validate_version!(@version), do: @version

  def validate_version!(version) do
    raise JSONCodec.Error,
      path: [:version],
      expected: @version,
      got: version,
      reason: :unsupported_plan_artifact_version
  end

  defp dump_change(%Change{} = change) do
    %{
      "action" => Resource.dump(change.action),
      "resource_id" => Resource.dump(change.resource_id),
      "before" => Resource.dump(change.before),
      "after" => Resource.dump(change.after),
      "reason" => Resource.dump(change.reason)
    }
  end

  defp load_change(%{} = change) do
    %Change{
      action: Resource.load(Map.fetch!(change, "action")),
      resource_id: Resource.load(Map.fetch!(change, "resource_id")),
      before: Resource.load(Map.fetch!(change, "before")),
      after: Resource.load(Map.fetch!(change, "after")),
      reason: Resource.load(Map.fetch!(change, "reason"))
    }
  end
end
