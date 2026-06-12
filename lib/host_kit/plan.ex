defmodule HostKit.Plan do
  @moduledoc "Structural plan generated from a HostKit project."

  alias HostKit.Addr
  alias HostKit.{Change, Project, Resource}

  @type t :: %__MODULE__{
          project: Project.t(),
          resources: [struct()],
          changes: [Change.t()],
          summary: map(),
          opts: keyword()
        }

  defstruct project: nil,
            resources: [],
            changes: [],
            summary: %{},
            opts: []

  @spec build(Project.t(), keyword()) :: {:ok, t()}
  def build(%Project{} = project, opts \\ []) do
    resources = Project.resources(project)

    changes = Enum.map(resources, &change_for(&1, project, opts))

    {:ok,
     %__MODULE__{
       project: project,
       resources: resources,
       changes: changes,
       summary: summarize(changes),
       opts: opts
     }}
  end

  defp change_for(resource, project, opts) do
    if ignored?(resource, opts) do
      build_change(:no_op, resource, nil, :ignored)
    else
      case Keyword.get(opts, :reader) do
        nil -> desired_change(resource)
        reader -> compare_with_actual(resource, reader, %{project: project, opts: opts})
      end
    end
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
      reason: reason
    }
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

  defp equivalent?(%HostKit.Caddy.Site{} = desired, actual) do
    normalize_caddy(Map.get(actual.meta, :content)) ==
      desired |> HostKit.Plugins.Caddy.render_site() |> IO.iodata_to_binary() |> normalize_caddy()
  end

  defp equivalent?(%HostKit.Resources.Directory{} = desired, actual),
    do: comparable(desired, actual, [:path, :owner, :group, :mode])

  defp equivalent?(%HostKit.Resources.File{content: content} = desired, actual)
       when content in [:redacted, :managed_elsewhere],
       do: comparable(desired, actual, [:path, :owner, :group, :mode])

  defp equivalent?(%HostKit.Resources.File{} = desired, actual),
    do: comparable(desired, actual, [:path, :content, :owner, :group, :mode])

  defp equivalent?(%HostKit.Resources.User{} = desired, actual),
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
