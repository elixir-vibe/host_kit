defmodule HostKit.Plan do
  @moduledoc "Structural plan generated from a HostKit project."

  alias HostKit.Addr
  alias HostKit.{Change, Diagnostic, Diagnostics, Project, Resource}
  alias HostKit.Package.{Manager, Resolver}

  alias HostKit.Resources.{
    Capability,
    Command,
    ConfigFile,
    Directory,
    EnvFile,
    Exs,
    File,
    Package,
    Source,
    Symlink,
    Template
  }

  @type t :: %__MODULE__{
          project: Project.t(),
          resources: [struct()],
          changes: [Change.t()],
          summary: map(),
          opts: keyword(),
          diagnostics: HostKit.Diagnostics.t()
        }

  defstruct project: nil,
            resources: [],
            changes: [],
            summary: %{},
            opts: [],
            diagnostics: %HostKit.Diagnostics{}

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%HostKit.Plan{} = plan, _opts) do
      counts = Enum.frequencies_by(plan.changes, & &1.action)
      project = if plan.project, do: " #{plan.project.name}", else: ""

      summary =
        [
          "#HostKit.Plan<",
          project,
          " create=",
          count(counts, :create),
          " update=",
          count(counts, :update),
          " delete=",
          count(counts, :delete),
          " read_errors=",
          count(counts, :read),
          " unchanged=",
          count(counts, :no_op),
          ">"
        ]

      concat(summary)
    end

    defp count(counts, action), do: counts |> Map.get(action, 0) |> Integer.to_string()
  end

  @spec build(Project.t(), keyword()) :: {:ok, t()} | {:error, HostKit.Diagnostics.t() | term()}
  def build(%Project{} = project, opts \\ []) do
    with :ok <- HostKit.RPC.validate(project),
         {:ok, services} <- Project.resolve_services(project, Keyword.get(opts, :services)) do
      opts = Keyword.put(opts, :services, services)
      resources = Project.resources(project, opts)
      opts = maybe_put_package_manager(resources, opts)

      build_resources(project, resources, opts)
    end
  end

  defp build_resources(project, resources, opts) do
    with {:ok, resources} <- resolve_resources(resources, opts),
         {:ok, resources} <- HostKit.Endpoint.Resolver.resolve(resources, project.services),
         {:ok, resources} <- expand_ingress(resources, project),
         :ok <- HostKit.CommandAnalysis.validate(resources),
         :ok <- maybe_write_package_lock(resources, opts) do
      opts = Keyword.put(opts, :resources, resources)
      changes = resources |> Enum.map(&change_for(&1, project, opts)) |> trigger_readiness()
      diagnostics = HostKit.Source.Diagnostics.for_plan(resources, changes)

      if HostKit.Diagnostics.ok?(diagnostics) do
        {:ok,
         %__MODULE__{
           project: project,
           resources: resources,
           changes: changes,
           summary: summarize(changes),
           opts: opts,
           diagnostics: diagnostics
         }}
      else
        {:error, diagnostics}
      end
    end
  end

  @doc "Builds a down/rollback plan from an existing plan."
  @spec down(t(), keyword()) :: {:ok, t()} | {:error, term()}
  def down(%__MODULE__{} = plan, opts \\ []) do
    selected = select_changes(plan.changes, opts)

    {changes, warnings} =
      selected
      |> Enum.reverse()
      |> Enum.reduce({[], []}, fn change, {changes, warnings} ->
        case down_change(change) do
          {:ok, down} -> {[down | changes], warnings}
          {:skip, nil} -> {changes, warnings}
          {:skip, warning} -> {changes, [warning | warnings]}
        end
      end)

    changes = Enum.reverse(changes)
    diagnostics = merge_down_warnings(plan.diagnostics, warnings)

    {:ok,
     %__MODULE__{
       plan
       | resources: Enum.map(changes, & &1.after) |> Enum.reject(&is_nil/1),
         changes: changes,
         summary:
           changes
           |> summarize()
           |> Map.put(:direction, :down)
           |> Map.put(:down, down_summary(selected, changes, warnings)),
         diagnostics: diagnostics,
         opts: Keyword.put(plan.opts, :direction, :down)
     }}
  end

  defp down_summary(selected, changes, warnings) do
    %{
      source_changes: length(selected),
      reversible: length(changes),
      noop: Enum.count(selected, &noop_down_change?/1),
      skipped: length(warnings)
    }
  end

  defp noop_down_change?(%Change{action: :create, after: %Command{down: :noop}}), do: true
  defp noop_down_change?(_change), do: false

  defp merge_down_warnings(%Diagnostics{} = diagnostics, warnings),
    do: %Diagnostics{diagnostics | warnings: diagnostics.warnings ++ warnings}

  defp select_changes(changes, opts) do
    only = opts |> Keyword.get(:only, []) |> List.wrap()
    except = opts |> Keyword.get(:except, []) |> List.wrap()

    Enum.filter(changes, fn change ->
      (only == [] or change.resource_id in only) and change.resource_id not in except
    end)
  end

  defp down_change(%Change{action: :update, before: nil} = change),
    do: {:skip, irreversible(change, :missing_previous_state)}

  defp down_change(%Change{action: :update, before: %Source{}} = change),
    do: {:skip, irreversible(change, :source_update_not_reversible)}

  defp down_change(%Change{action: :update, before: before} = change) do
    {:ok,
     %Change{
       action: :update,
       resource_id: change.resource_id,
       before: change.after,
       after: before,
       reason: {:down, change.reason}
     }}
  end

  defp down_change(
         %Change{action: :create, after: %Command{down: %Command{} = down_command}} = change
       ) do
    {:ok,
     %Change{
       action: :create,
       resource_id: Resource.id(down_command),
       before: nil,
       after: down_command,
       reason: {:down, change.resource_id}
     }}
  end

  defp down_change(%Change{action: :create, after: %Command{down: :noop}}), do: {:skip, nil}

  defp down_change(%Change{action: :create, after: %Command{down: :irreversible}} = change),
    do: {:skip, irreversible(change, :explicitly_irreversible)}

  defp down_change(%Change{action: :create, after: %Command{down: nil}} = change),
    do: {:skip, irreversible(change, :missing_down_command)}

  defp down_change(%Change{action: :create, after: resource} = change) do
    if delete_supported?(resource) do
      {:ok,
       %Change{
         action: :delete,
         resource_id: change.resource_id,
         before: resource,
         after: nil,
         reason: {:down, change.reason}
       }}
    else
      {:skip, irreversible(change, :delete_not_supported)}
    end
  end

  defp down_change(%Change{action: :delete, before: nil} = change),
    do: {:skip, irreversible(change, :missing_previous_state)}

  defp down_change(%Change{action: :delete, before: before} = change) do
    {:ok,
     %Change{
       action: :create,
       resource_id: change.resource_id,
       before: nil,
       after: before,
       reason: {:down, change.reason}
     }}
  end

  defp down_change(%Change{} = change), do: {:skip, irreversible(change, :not_applied_change)}

  defp delete_supported?(%ConfigFile{}), do: true
  defp delete_supported?(%File{}), do: true
  defp delete_supported?(%EnvFile{}), do: true
  defp delete_supported?(%Directory{rollback: :delete_if_created}), do: true
  defp delete_supported?(%Directory{}), do: false
  defp delete_supported?(%Symlink{}), do: true
  defp delete_supported?(%Template{}), do: true
  defp delete_supported?(%Exs{}), do: true
  defp delete_supported?(%HostKit.Firewall{}), do: true
  defp delete_supported?(%HostKit.Proxy{}), do: true
  defp delete_supported?(%HostKit.Instance{lifecycle: :ephemeral}), do: true
  defp delete_supported?(%HostKit.Systemd.Service{}), do: true
  defp delete_supported?(%HostKit.Systemd.Timer{}), do: true
  defp delete_supported?(_resource), do: false

  defp irreversible(%Change{} = change, reason) do
    %Diagnostic{
      severity: :warning,
      code: :irreversible_change,
      message: "change cannot be represented in a down plan: #{inspect(reason)}",
      resource_id: change.resource_id,
      details: %{reason: reason, action: change.action},
      hint:
        "HostKit keeps rollback as a plan; unsupported resources are omitted from the down plan."
    }
  end

  defp trigger_readiness(changes) do
    plan = %__MODULE__{changes: changes}
    graph = HostKit.Plan.ExecutionGraph.build(plan, include: :all)
    active = active_resource_ids(changes)
    incoming = incoming_edges(graph.edges)

    Enum.map(changes, &trigger_readiness_change(&1, active, incoming))
  end

  defp active_resource_ids(changes) do
    changes
    |> Enum.filter(&(&1.action in [:create, :update, :delete]))
    |> MapSet.new(& &1.resource_id)
  end

  defp incoming_edges(edges) do
    Enum.group_by(edges, & &1.to, & &1.from)
  end

  defp trigger_readiness_change(
         %Change{action: :no_op, after: %HostKit.Resources.Readiness{}} = change,
         active,
         incoming
       ) do
    case active_dependencies(change.resource_id, active, incoming) do
      [] -> change
      dependencies -> %Change{change | action: :update, reason: {:triggered_by, dependencies}}
    end
  end

  defp trigger_readiness_change(change, _active, _incoming), do: change

  defp active_dependencies(resource_id, active, incoming) do
    resource_id
    |> collect_active_dependencies(active, incoming, MapSet.new())
    |> MapSet.to_list()
    |> Enum.sort_by(&inspect/1)
  end

  defp collect_active_dependencies(resource_id, active, incoming, visited) do
    if MapSet.member?(visited, resource_id) do
      MapSet.new()
    else
      visited = MapSet.put(visited, resource_id)

      incoming
      |> Map.get(resource_id, [])
      |> Enum.reduce(MapSet.new(), fn dependency, dependencies ->
        dependencies =
          if MapSet.member?(active, dependency),
            do: MapSet.put(dependencies, dependency),
            else: dependencies

        MapSet.union(
          dependencies,
          collect_active_dependencies(dependency, active, incoming, visited)
        )
      end)
    end
  end

  defp maybe_put_package_manager(resources, opts) do
    if Keyword.has_key?(opts, :reader) and package_resources_present?(resources) and
         not Keyword.has_key?(opts, :package_manager) do
      case Manager.detect(opts) do
        {:ok, manager} -> Keyword.put(opts, :package_manager, manager)
        {:error, _reason} -> opts
      end
    else
      opts
    end
  end

  defp package_resources_present?(resources), do: Enum.any?(resources, &package_resource?/1)
  defp package_resource?(%Package{}), do: true
  defp package_resource?(%Capability{}), do: true
  defp package_resource?(_resource), do: false

  defp resolve_resources(resources, opts) do
    resources
    |> Enum.reduce_while({:ok, []}, &resolve_resource_step(&1, &2, opts))
    |> then(fn
      {:ok, resources} -> {:ok, Enum.reverse(resources)}
      error -> error
    end)
  end

  defp resolve_resource_step(resource, {:ok, resolved}, opts) do
    case timed_resource(:resolve, resource, fn -> resolve_resource(resource, opts) end) do
      {:ok, resource} -> {:cont, {:ok, [resource | resolved]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp expand_ingress(resources, project) do
    {:ok, Enum.flat_map(resources, &expand_ingress_resource(&1, project))}
  end

  defp expand_ingress_resource(%HostKit.Ingress{} = ingress, project) do
    []
    |> maybe_expand_caddy_ingress(ingress, project)
    |> maybe_expand_gatehouse_ingress(ingress, project)
    |> case do
      [] -> [ingress]
      resources -> resources
    end
  end

  defp expand_ingress_resource(resource, _project), do: [resource]

  defp maybe_expand_caddy_ingress(resources, ingress, project) do
    if HostKit.Providers.Caddy in project.providers,
      do: resources ++ HostKit.Ingress.Caddy.to_sites(ingress),
      else: resources
  end

  defp maybe_expand_gatehouse_ingress(resources, ingress, project) do
    if HostKit.Providers.Gatehouse in project.providers,
      do: resources ++ [HostKit.Ingress.Gatehouse.to_proxy(ingress)],
      else: resources
  end

  defp timed_resource(phase, resource, fun) do
    HostKit.Telemetry.span([:plan, :resource], resource_metadata(phase, resource), fun)
  end

  defp resource_metadata(phase, resource) do
    %{phase: phase, resource_id: Resource.id(resource), resource_module: resource.__struct__}
  end

  defp resolve_resource(%Package{} = package, opts), do: Resolver.resolve(package, opts)

  defp resolve_resource(%Capability{} = capability, opts), do: Resolver.resolve(capability, opts)

  defp resolve_resource(%Template{} = template, _opts) do
    if Template.secret?(template) do
      {:ok, template}
    else
      case Template.render(template) do
        {:ok, _content} -> {:ok, template}
        {:error, reason} -> {:error, {:template_render_failed, Template.id(template), reason}}
      end
    end
  end

  defp resolve_resource(%Exs{} = exs, _opts) do
    if Exs.secret?(exs) do
      {:ok, exs}
    else
      case Exs.render(exs) do
        {:ok, _content} -> {:ok, exs}
        {:error, reason} -> {:error, {:exs_render_failed, Exs.id(exs), reason}}
      end
    end
  end

  defp resolve_resource(%Source{} = source, _opts) do
    case HostKit.Source.Git.resolve(source) do
      {:ok, source} -> {:ok, source}
      {:error, reason} -> {:error, HostKit.Source.Diagnostics.resolution_error(source, reason)}
    end
  end

  defp resolve_resource(resource, _opts), do: {:ok, resource}

  defp maybe_write_package_lock(resources, opts) do
    case Keyword.get(opts, :package_lock_write) do
      path when is_binary(path) -> write_package_lock(path, resources)
      _other -> :ok
    end
  end

  defp write_package_lock(path, resources) do
    lock =
      Enum.reduce(resources, %HostKit.Package.Lock{}, fn
        %HostKit.Resources.Package{meta: %{resolution: resolution}, name: name}, lock ->
          HostKit.Package.Lock.put(lock, name, resolution.package, resolution.repo)

        _resource, lock ->
          lock
      end)

    HostKit.Package.Lock.save(path, lock)
  end

  defp change_for(resource, project, opts) do
    if ignored?(resource, opts) do
      build_change(:no_op, resource, nil, :ignored)
    else
      observed_change_for(resource, project, opts, Keyword.get(opts, :reader))
    end
  end

  defp observed_change_for(resource, _project, _opts, nil), do: desired_change(resource)

  defp observed_change_for(resource, project, opts, reader) do
    opts = resource_opts(resource, opts)
    reader = Keyword.get(opts, :reader, reader)

    timed_resource(:read, resource, fn ->
      compare_with_actual(resource, reader, %{project: project, opts: opts})
    end)
  end

  defp resource_opts(resource, opts) do
    resource
    |> resource_target_opts()
    |> expand_target_opts()
    |> merge_resource_opts(opts)
  end

  defp resource_target_opts(%{meta: %{target_opts: target_opts}}) when is_list(target_opts),
    do: target_opts

  defp resource_target_opts(_resource), do: []

  defp expand_target_opts(opts) do
    case Keyword.pop(opts, :target) do
      {%HostKit.Target{} = target, opts} -> HostKit.Target.opts(target, opts)
      {_other, opts} -> opts
    end
  end

  defp merge_resource_opts([], opts), do: opts

  defp merge_resource_opts(resource_opts, opts) do
    opts
    |> Keyword.drop([:conn])
    |> Keyword.merge(resource_opts)
  end

  defp ignored?(resource, opts) do
    resource_id = Resource.id(resource)

    opts
    |> Keyword.get(:ignore, [])
    |> List.wrap()
    |> Enum.any?(&(&1 == resource_id))
  end

  defp desired_change(resource) do
    build_change(:create, resource, nil, :desired_state)
  end

  defp compare_with_actual(resource, reader, context) do
    case read_actual(reader, resource, context) do
      {:ok, nil} -> build_change(:create, resource, nil, :missing)
      {:ok, actual} -> diff_change(resource, actual)
      {:error, reason} -> build_change(:read, resource, nil, {:read_error, reason})
    end
  end

  defp read_actual(reader, resource, context) do
    Code.ensure_loaded?(reader)

    cond do
      function_exported?(reader, :read, 2) -> reader.read(resource, context)
      function_exported?(reader, :read, 1) -> reader.read(resource)
      true -> {:error, {:missing_reader_callback, reader}}
    end
  end

  defp diff_change(resource, actual) do
    if equivalent?(resource, actual) do
      build_change(:no_op, resource, actual, :in_sync)
    else
      build_change(:update, resource, actual, :drift)
    end
  end

  defp build_change(action, resource, actual, reason) do
    %Change{
      action: action,
      resource_id: Resource.id(resource),
      before: actual,
      after: resource,
      reason: reason,
      diff: diff_for(action, resource, actual)
    }
  end

  defp diff_for(:update, %ConfigFile{} = desired, actual) do
    actual_entries = config_actual_entries(desired, actual)
    diff = HostKit.Diff.config_file(desired, actual_entries)
    if HostKit.Diff.empty?(diff), do: nil, else: diff
  end

  defp diff_for(:update, %HostKit.Resources.EnvFile{} = desired, actual) do
    actual_entries = Map.get(actual.meta, :actual_public_entries)
    diff = HostKit.Diff.env_file(desired, actual_entries)
    if HostKit.Diff.empty?(diff), do: nil, else: diff
  end

  defp diff_for(:update, %Template{} = desired, actual) do
    diff = HostKit.Diff.template(desired, template_actual_assigns(actual))
    if HostKit.Diff.empty?(diff), do: nil, else: diff
  end

  defp diff_for(_action, _resource, _actual), do: nil

  defp template_actual_assigns(%Template{meta: %{actual_public_assigns: assigns}})
       when is_map(assigns),
       do: %Template{assigns: assigns}

  defp template_actual_assigns(_actual), do: nil

  defp config_actual_entries(%ConfigFile{} = desired, actual) do
    cond do
      Map.has_key?(actual.meta, :actual_public_entries) ->
        Map.fetch!(actual.meta, :actual_public_entries)

      is_binary(Map.get(actual.meta, :content)) ->
        case ConfigFile.public_entries_from_content(desired, actual.meta.content) do
          {:ok, entries} -> entries
          {:error, _reason} -> :invalid
        end

      true ->
        nil
    end
  end

  defp equivalent?(%HostKit.Systemd.Service{} = desired, actual) do
    Systemd.UnitFile.equivalent?(
      Map.get(actual.meta, :content),
      HostKit.Systemd.Service.render(desired)
    )
  end

  defp equivalent?(%HostKit.Systemd.Timer{} = desired, actual) do
    Systemd.UnitFile.equivalent?(
      Map.get(actual.meta, :content),
      HostKit.Systemd.Timer.render(desired)
    )
  end

  defp equivalent?(%HostKit.Instance{} = desired, actual) do
    comparable(desired, actual, [:name, :backend, :image, :kind, :lifecycle, :ports])
  end

  defp equivalent?(%HostKit.Workspace.Egress{} = desired, actual) do
    Map.get(actual.meta, :content) == HostKit.Firewall.Nftables.render_egress(desired)
  end

  defp equivalent?(%HostKit.Firewall{} = desired, actual) do
    Map.get(actual.meta, :content) == HostKit.Firewall.render(desired)
  end

  defp equivalent?(%HostKit.Proxy{} = desired, actual) do
    Map.get(actual.meta, :content) == HostKit.Proxy.render(desired)
  end

  defp equivalent?(%HostKit.Resources.Mise{} = desired, actual) do
    installed = MapSet.new(Map.get(actual.meta, :installed_tools, []))
    desired.tools |> Enum.map(&{&1.name, &1.version}) |> MapSet.new() |> MapSet.subset?(installed)
  end

  defp equivalent?(%HostKit.Resources.Package{version: nil}, actual),
    do: Map.get(actual.meta, :installed) == true

  defp equivalent?(%HostKit.Resources.Package{version: version}, actual),
    do: Map.get(actual.meta, :installed) == true and Map.get(actual.meta, :version) == version

  defp equivalent?(%HostKit.Caddy.Site{} = desired, actual) do
    normalize_caddy(Map.get(actual.meta, :content)) ==
      desired
      |> HostKit.Providers.Caddy.render_site()
      |> IO.iodata_to_binary()
      |> normalize_caddy()
  end

  defp equivalent?(%HostKit.Resources.Directory{} = desired, actual),
    do: comparable(desired, actual, [:path, :owner, :group, :mode])

  defp equivalent?(%HostKit.Resources.File{content: content} = desired, actual)
       when content in [:redacted, :managed_elsewhere],
       do: comparable(desired, actual, [:path, :owner, :group, :mode])

  defp equivalent?(%HostKit.Resources.File{} = desired, actual),
    do: comparable(desired, actual, [:path, :content, :owner, :group, :mode])

  defp equivalent?(%ConfigFile{} = desired, actual) do
    if ConfigFile.secret?(desired) do
      comparable(desired, actual, [:path, :format, :owner, :group, :mode]) and
        ConfigFile.public_entries(desired) == Map.get(actual.meta, :actual_public_entries, %{})
    else
      {:ok, content} = ConfigFile.render(desired)

      comparable(desired, actual, [:path, :format, :owner, :group, :mode]) and
        Map.get(actual.meta, :content) == content
    end
  end

  defp equivalent?(%Template{} = desired, actual) do
    if Template.secret?(desired) do
      false
    else
      case Template.render(desired) do
        {:ok, content} ->
          comparable(desired, actual, [:path, :owner, :group, :mode]) and
            Map.get(actual.meta, :content) == content

        {:error, _reason} ->
          false
      end
    end
  end

  defp equivalent?(%Exs{} = desired, actual) do
    if Exs.secret?(desired) do
      false
    else
      case Exs.render(desired) do
        {:ok, content} ->
          comparable(desired, actual, [:path, :owner, :group, :mode]) and
            Map.get(actual.meta, :content) == content

        {:error, _reason} ->
          false
      end
    end
  end

  defp equivalent?(%Symlink{} = desired, actual),
    do: comparable(desired, actual, [:path, :to, :owner, :group])

  defp equivalent?(%HostKit.Resources.EnvFile{} = desired, actual) do
    comparable(desired, actual, [:path, :owner, :group, :mode]) and
      HostKit.Env.public_entries(desired) == Map.get(actual.meta, :actual_public_entries, %{})
  end

  defp equivalent?(%Source{} = desired, %Source{} = actual) do
    comparable(desired, actual, [:type, :uri, :revision]) and
      not Map.get(actual.meta, :dirty, false)
  end

  defp equivalent?(%HostKit.Resources.Account{} = desired, actual),
    do: comparable(desired, actual, [:name, :home, :shell, :groups])

  defp equivalent?(desired, actual), do: desired == actual

  defp normalize_caddy(nil), do: nil

  defp normalize_caddy(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp comparable(desired, actual, fields) do
    Enum.all?(fields, fn field ->
      desired_value = Map.get(desired, field)
      is_nil(desired_value) or desired_value == Map.get(actual, field)
    end)
  end

  defp summarize(changes) do
    changes
    |> Enum.map(& &1.resource_id)
    |> Enum.frequencies_by(&resource_type/1)
  end

  defp resource_type(%Addr.Resource{type: type}), do: type
  defp resource_type({type, _name}), do: type
  defp resource_type(other), do: other
end
