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
end
