defmodule HostKit.Source.Identity do
  @moduledoc "Semantic identity/provenance for a declared source."

  @type t :: %__MODULE__{
          type: atom(),
          uri: String.t(),
          ref: String.t(),
          ref_kind: atom(),
          revision: String.t() | nil,
          tree: String.t() | nil,
          checkout: String.t(),
          path: String.t()
        }

  defstruct [:type, :uri, :ref, :ref_kind, :revision, :tree, :checkout, :path]

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = identity) do
    %{
      "type" => Atom.to_string(identity.type),
      "uri" => identity.uri,
      "ref" => identity.ref,
      "ref_kind" => Atom.to_string(identity.ref_kind),
      "revision" => identity.revision,
      "tree" => identity.tree,
      "checkout" => identity.checkout,
      "path" => identity.path
    }
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(identity, _opts) do
      revision = short_revision(identity.revision)
      path = if identity.path in [nil, "."], do: "", else: " path=#{identity.path}"

      concat([
        "#HostKit.Source.Identity<",
        to_string(identity.type),
        " ",
        identity.uri || "",
        "@",
        revision || identity.ref || "unknown",
        path,
        ">"
      ])
    end

    defp short_revision(nil), do: nil
    defp short_revision(revision) when byte_size(revision) > 12, do: binary_part(revision, 0, 12)
    defp short_revision(revision), do: revision
  end
end
