defmodule HostKit.Plan.Artifact do
  @moduledoc "Portable JSON artifact for a resolved HostKit plan."

  use JSONCodec, fast_path: :json

  alias HostKit.{Change, Plan, Resource}

  @artifact_modules MapSet.new([
                      HostKit.Addr.AbsResource,
                      HostKit.Addr.Resource,
                      HostKit.Caddy.Directive.Encode,
                      HostKit.Caddy.Directive.FileServer,
                      HostKit.Caddy.Directive.ReverseProxy,
                      HostKit.Caddy.Directive.Root,
                      HostKit.Caddy.Site,
                      HostKit.Change,
                      HostKit.Apply.Event,
                      HostKit.Backup.Job,
                      HostKit.Backup.Service,
                      HostKit.BackupRef,
                      HostKit.CommandLine,
                      HostKit.Conventions,
                      HostKit.Diagnostic,
                      HostKit.Diagnostics,
                      HostKit.Diff,
                      HostKit.Diff.Entry,
                      HostKit.Endpoint,
                      HostKit.Firewall,
                      HostKit.Firewall.Rule,
                      HostKit.Host,
                      HostKit.Ingress,
                      HostKit.Ingress.Proxy,
                      HostKit.Ingress.Route,
                      HostKit.Ingress.Server,
                      HostKit.Ingress.TLS,
                      HostKit.Instance,
                      HostKit.Listener,
                      HostKit.Monitor,
                      HostKit.Monitor.Check,
                      HostKit.Monitor.Endpoint,
                      HostKit.Monitor.Result,
                      HostKit.Package.Resolution,
                      HostKit.Project,
                      HostKit.ProviderConfig,
                      HostKit.Proxy,
                      HostKit.RPC,
                      HostKit.RPC.Binding,
                      HostKit.RPC.Exposure,
                      HostKit.Account.Ref,
                      HostKit.Resources.Account,
                      HostKit.Resources.Capability,
                      HostKit.Resources.Command,
                      HostKit.Resources.ConfigFile,
                      HostKit.Resources.Directory,
                      HostKit.Resources.EnvFile,
                      HostKit.Resources.Exs,
                      HostKit.Resources.File,
                      HostKit.Resources.Mise,
                      HostKit.Resources.Package,
                      HostKit.Resources.Readiness,
                      HostKit.Resources.Shell,
                      HostKit.Resources.Source,
                      HostKit.Resources.Symlink,
                      HostKit.Resources.Template,
                      HostKit.Secret,
                      HostKit.Readiness.HTTP,
                      HostKit.Readiness.Systemd,
                      HostKit.Source.Identity,
                      HostKit.Service,
                      HostKit.Storage.Volume,
                      HostKit.ShellScript,
                      HostKit.Systemd.Service,
                      HostKit.Systemd.Timer,
                      HostKit.Tenant,
                      HostKit.Workspace.Egress,
                      Range
                    ])
  @artifact_module_names @artifact_modules |> Enum.map(&Atom.to_string/1) |> MapSet.new()

  @doc "Decodes a JSON-safe artifact term."
  @spec load_term(term()) :: term()
  def load_term(%{"$type" => "struct", "module" => module, "fields" => fields}) do
    module = allowed_artifact_module!(module)
    struct(module, load_struct_fields(fields, module))
  end

  def load_term(%{"$type" => "tuple", "items" => items}),
    do: items |> load_term() |> List.to_tuple()

  def load_term(%{"$type" => "map", "entries" => entries}) do
    Map.new(entries, fn [key, value] -> {load_term(key), load_term(value)} end)
  end

  def load_term(%{"$type" => "atom", "value" => value}), do: load_atom(value)

  def load_term(%{"$type" => "binary", "encoding" => "base64", "value" => value}) do
    Base.decode64!(value)
  end

  def load_term(values) when is_list(values), do: Enum.map(values, &load_term/1)
  def load_term(value), do: value

  defp load_struct_fields(fields, module) when is_map(fields) do
    known_fields = struct_field_names(module)

    Map.new(fields, fn {key, value} ->
      {Map.fetch!(known_fields, key), load_term(value)}
    end)
  end

  defp struct_field_names(module) do
    module
    |> struct()
    |> Map.from_struct()
    |> Map.keys()
    |> Map.new(&{Atom.to_string(&1), &1})
  end

  defp load_atom(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp allowed_artifact_module!(module) when is_atom(module) do
    if MapSet.member?(@artifact_modules, module) do
      module
    else
      raise ArgumentError, "unsupported HostKit artifact module #{inspect(module)}"
    end
  end

  defp allowed_artifact_module!(module) when is_binary(module) do
    if MapSet.member?(@artifact_module_names, module) do
      String.to_existing_atom(module)
    else
      raise ArgumentError, "unsupported HostKit artifact module #{inspect(module)}"
    end
  end

  defmodule ChangeEntry do
    @moduledoc "Serialized change entry stored in a portable plan artifact."

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

    codec(:resource_id, transform: &HostKit.Plan.Artifact.load_term/1)
    codec(:before, transform: &HostKit.Plan.Artifact.load_term/1)
    codec(:after, transform: &HostKit.Plan.Artifact.load_term/1)
    codec(:reason, transform: &HostKit.Plan.Artifact.load_term/1)
    codec(:diff, transform: &HostKit.Plan.Artifact.load_term/1)

    def from_change(%Change{} = change) do
      %__MODULE__{
        action: change.action,
        resource_id: HostKit.Resource.dump(change.resource_id),
        before: HostKit.Resource.dump(change.before),
        after: HostKit.Resource.dump(change.after),
        reason: HostKit.Resource.dump(change.reason),
        diff: HostKit.Resource.dump(change.diff),
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
            diagnostics: %{
              "$type" => "struct",
              "module" => "Elixir.HostKit.Diagnostics",
              "fields" => %{"errors" => [], "warnings" => []}
            }

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
       project: HostKit.Plan.Artifact.load_term(artifact.project),
       resources: HostKit.Plan.Artifact.load_term(artifact.resources),
       changes: Enum.map(artifact.changes, &ChangeEntry.to_change/1),
       summary: HostKit.Plan.Artifact.load_term(artifact.summary),
       opts: [],
       diagnostics: HostKit.Plan.Artifact.load_term(artifact.diagnostics)
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
      HostKit.Runner.Files.write_file(path, [content, ?\n], mode: 0o600)
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
