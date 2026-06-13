defmodule HostKit.Source.Diagnostics do
  @moduledoc false

  alias HostKit.{Change, Diagnostic, Diagnostics, Resource}
  alias HostKit.Resources.Source

  @spec for_plan([struct()], [Change.t()]) :: Diagnostics.t()
  def for_plan(resources, changes) do
    (Enum.flat_map(resources, &resource_diagnostics/1) ++
       Enum.flat_map(changes, &change_diagnostics/1))
    |> Diagnostics.new()
  end

  @spec resolution_error(Source.t(), term()) :: Diagnostics.t()
  def resolution_error(%Source{} = source, reason) do
    Diagnostics.new([
      %Diagnostic{
        severity: :error,
        code: :source_ref_unresolved,
        message:
          "source #{inspect(source.name)} ref #{inspect(source.ref)} could not be resolved",
        resource_id: Resource.id(source),
        file: get_in(source.meta, [:source, :file]),
        line: get_in(source.meta, [:source, :line]),
        column: get_in(source.meta, [:source, :column]),
        details: %{uri: source.uri, ref: source.ref, reason: reason},
        hint: "Check the source URI/ref or pin the source to a reachable revision."
      }
    ])
  end

  defp resource_diagnostics(%Source{type: :git, ref_kind: :branch} = source) do
    [
      %Diagnostic{
        severity: :warning,
        code: :source_mutable_ref,
        message: "source #{inspect(source.name)} uses mutable git ref #{inspect(source.ref)}",
        resource_id: Resource.id(source),
        file: get_in(source.meta, [:source, :file]),
        line: get_in(source.meta, [:source, :line]),
        column: get_in(source.meta, [:source, :column]),
        details: %{uri: source.uri, ref: source.ref, revision: source.revision},
        hint:
          "This plan pins the resolved revision; use a commit revision for fully reproducible declarations."
      }
    ]
  end

  defp resource_diagnostics(_resource), do: []

  defp change_diagnostics(%Change{
         after: %Source{dirty: :error} = source,
         before: %Source{} = actual
       }) do
    if Map.get(actual.meta, :dirty, false) do
      [
        %Diagnostic{
          severity: :error,
          code: :source_checkout_dirty,
          message: "source #{inspect(source.name)} checkout is dirty",
          resource_id: Resource.id(source),
          file: get_in(source.meta, [:source, :file]),
          line: get_in(source.meta, [:source, :line]),
          column: get_in(source.meta, [:source, :column]),
          details: %{
            checkout: source.checkout,
            status: Map.get(actual.meta, :status)
          },
          hint:
            "Clean the checkout or set `dirty: :reset` if HostKit should discard local changes."
        }
      ]
    else
      drift_diagnostics(source, actual)
    end
  end

  defp change_diagnostics(%Change{after: %Source{} = source, before: %Source{} = actual}) do
    drift_diagnostics(source, actual)
  end

  defp change_diagnostics(%Change{after: %Source{} = source, reason: {:read_error, reason}}) do
    [read_error_diagnostic(source, reason)]
  end

  defp change_diagnostics(_change), do: []

  defp drift_diagnostics(source, actual) do
    []
    |> maybe_add_uri_drift(source, actual)
    |> maybe_add_revision_drift(source, actual)
  end

  defp maybe_add_uri_drift(diagnostics, %Source{uri: uri} = source, %Source{uri: actual_uri})
       when uri != actual_uri do
    [
      %Diagnostic{
        severity: :warning,
        code: :source_uri_drift,
        message: "source #{inspect(source.name)} remote URL differs from desired URI",
        resource_id: Resource.id(source),
        details: %{desired_uri: uri, current_uri: actual_uri},
        hint: "Apply the plan to update the source remote URL."
      }
      | diagnostics
    ]
  end

  defp maybe_add_uri_drift(diagnostics, _source, _actual), do: diagnostics

  defp maybe_add_revision_drift(diagnostics, %Source{revision: revision} = source, %Source{
         revision: actual_revision
       })
       when is_binary(revision) and revision != actual_revision do
    [
      %Diagnostic{
        severity: :warning,
        code: :source_revision_drift,
        message:
          "source #{inspect(source.name)} checkout revision differs from resolved revision",
        resource_id: Resource.id(source),
        details: %{desired_revision: revision, current_revision: actual_revision},
        hint: "Apply the plan to check out the pinned source revision."
      }
      | diagnostics
    ]
  end

  defp maybe_add_revision_drift(diagnostics, _source, _actual), do: diagnostics

  defp read_error_diagnostic(source, {:source_checkout_not_git, checkout}) do
    %Diagnostic{
      severity: :error,
      code: :source_checkout_not_git,
      message: "source #{inspect(source.name)} checkout path exists but is not a git repository",
      resource_id: Resource.id(source),
      file: get_in(source.meta, [:source, :file]),
      line: get_in(source.meta, [:source, :line]),
      column: get_in(source.meta, [:source, :column]),
      details: %{checkout: checkout},
      hint: "Remove the path or choose a different checkout directory."
    }
  end

  defp read_error_diagnostic(source, reason) do
    %Diagnostic{
      severity: :error,
      code: :source_read_error,
      message: "source #{inspect(source.name)} could not be inspected",
      resource_id: Resource.id(source),
      file: get_in(source.meta, [:source, :file]),
      line: get_in(source.meta, [:source, :line]),
      column: get_in(source.meta, [:source, :column]),
      details: %{reason: reason},
      hint: "Check the checkout path and target git installation."
    }
  end
end
