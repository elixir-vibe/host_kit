defmodule HostKit.Plan.Artifact do
  @moduledoc "Portable JSON artifact for a resolved HostKit plan."

  use JSONCodec, fast_path: :json

  alias HostKit.{Change, Plan, Resource}

  defmodule ChangeEntry do
    @moduledoc false

    use JSONCodec, fast_path: :json

    defstruct action: nil,
              resource_id: nil,
              before: nil,
              after: nil,
              reason: nil,
              diff: nil,
              source: nil

    @type t :: %__MODULE__{
            action: :create | :update | :delete | :no_op | :read,
            resource_id: term(),
            before: term(),
            after: term(),
            reason: term(),
            diff: term(),
            source: map() | nil
          }

    codec(:resource_id, transform: &Resource.load/1)
    codec(:before, transform: &Resource.load/1)
    codec(:after, transform: &Resource.load/1)
    codec(:reason, transform: &Resource.load/1)
    codec(:diff, transform: &Resource.load/1)

    def from_change(%Change{} = change) do
      %__MODULE__{
        action: change.action,
        resource_id: Resource.dump(change.resource_id),
        before: Resource.dump(change.before),
        after: Resource.dump(change.after),
        reason: Resource.dump(change.reason),
        diff: Resource.dump(change.diff),
        source: change_source(change)
      }
    end

    def to_change(%__MODULE__{} = entry) do
      %Change{
        action: entry.action,
        resource_id: entry.resource_id,
        before: entry.before,
        after: entry.after,
        reason: entry.reason,
        diff: entry.diff
      }
    end

    defp change_source(%Change{after: %{meta: %{source: source}}}) when is_map(source), do: source

    defp change_source(%Change{before: %{meta: %{source: source}}}) when is_map(source),
      do: source

    defp change_source(_change), do: nil
  end

  @version 1

  defstruct version: @version,
            generated_at: nil,
            target: nil,
            project: nil,
            resources: [],
            sources: %{},
            changes: [],
            summary: %{},
            stats: %{},
            diagnostics: Resource.dump(%HostKit.Diagnostics{})

  @type t :: %__MODULE__{
          version: pos_integer(),
          generated_at: String.t() | nil,
          target: map() | nil,
          project: term(),
          resources: [term()],
          sources: map(),
          changes: [ChangeEntry.t()],
          summary: term(),
          stats: map(),
          diagnostics: term()
        }

  codec(:version, transform: :validate_version!)

  @spec from_plan(Plan.t(), keyword()) :: t()
  def from_plan(%Plan{} = plan, opts \\ []) do
    %__MODULE__{
      generated_at:
        Keyword.get_lazy(opts, :generated_at, &DateTime.utc_now/0) |> DateTime.to_iso8601(),
      target: Keyword.get(opts, :target_metadata, %{}),
      project: Resource.dump(plan.project),
      resources: Resource.dump(plan.resources),
      sources: source_identities(plan.resources),
      changes: Enum.map(plan.changes, &ChangeEntry.from_change/1),
      summary: Resource.dump(plan.summary),
      stats: HostKit.Plan.Summary.artifact_stats(plan),
      diagnostics: Resource.dump(plan.diagnostics)
    }
  end

  @spec to_plan(t()) :: {:ok, Plan.t()} | {:error, term()}
  def to_plan(%__MODULE__{} = artifact) do
    {:ok,
     %Plan{
       project: Resource.load(artifact.project),
       resources: Resource.load(artifact.resources),
       changes: Enum.map(artifact.changes, &ChangeEntry.to_change/1),
       summary: Resource.load(artifact.summary),
       opts: [],
       diagnostics: Resource.load(artifact.diagnostics)
     }}
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  @spec load(Path.t(), keyword()) :: {:ok, Plan.t()} | {:error, term()}
  def load(path, opts \\ []) do
    with {:ok, artifact} <- load_artifact(path, opts) do
      to_plan(artifact)
    end
  end

  @spec load_artifact(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def load_artifact(path, opts \\ []) do
    with {:ok, content} <- read_artifact(path, opts) do
      decode(content)
    end
  end

  defp read_artifact(path, opts), do: HostKit.Runner.read_file(path, opts)

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

  defp source_identities(resources) do
    resources
    |> Enum.filter(&match?(%HostKit.Resources.Source{}, &1))
    |> Map.new(fn source ->
      {to_string(source.name),
       source |> HostKit.Resources.Source.identity() |> HostKit.Source.Identity.dump()}
    end)
  end
end
