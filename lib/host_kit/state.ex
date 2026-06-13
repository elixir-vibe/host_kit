defmodule HostKit.State do
  @moduledoc "State snapshot persistence for HostKit plans and agent status."

  @version 1

  @spec snapshot(HostKit.Plan.t() | map(), keyword()) :: map()
  def snapshot(subject, opts \\ []) do
    %{
      version: @version,
      written_at: DateTime.utc_now(),
      kind: kind(subject),
      name: name(subject),
      data: data(subject),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @spec write(HostKit.Plan.t() | map(), Path.t(), keyword()) :: :ok | {:error, term()}
  def write(subject, path, opts \\ []) do
    content =
      subject
      |> snapshot(opts)
      |> encode!()

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, content)
    end
  end

  @spec read(Path.t()) :: {:ok, map()} | {:error, term()}
  def read(path) do
    path
    |> File.read()
    |> then(fn
      {:ok, content} -> Jason.decode(content, keys: :atoms)
      error -> error
    end)
  end

  defp encode!(snapshot) do
    Jason.encode!(snapshot, pretty: true)
  end

  defp kind(%HostKit.Plan{}), do: :plan
  defp kind(%{started_at: _, events: _}), do: :agent_status
  defp kind(_subject), do: :unknown

  defp name(%HostKit.Plan{project: %HostKit.Project{name: name}}), do: name
  defp name(%{project: project}), do: project
  defp name(_subject), do: nil

  defp data(%HostKit.Plan{} = plan) do
    %{
      project: name(plan),
      summary: plan.summary,
      resources: Enum.map(plan.resources, &safe_resource/1),
      changes: Enum.map(plan.changes, &safe_change/1)
    }
  end

  defp data(subject), do: subject

  defp safe_change(change) do
    %{
      action: change.action,
      resource_id: encode_term(change.resource_id),
      reason: encode_term(change.reason),
      before: safe_resource(change.before),
      after: safe_resource(change.after)
    }
  end

  defp safe_resource(nil), do: nil

  defp safe_resource(resource) do
    %{
      type: resource.__struct__,
      id: encode_term(HostKit.Resource.id(resource)),
      inspect: inspect(resource)
    }
  end

  defp encode_term(term)
       when is_atom(term) or is_binary(term) or is_number(term) or is_boolean(term) or
              is_nil(term),
       do: term

  defp encode_term(term), do: inspect(term)
end
