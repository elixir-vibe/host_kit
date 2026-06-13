defmodule HostKit.Resources.Source do
  @moduledoc "Desired source checkout. Git is the first supported backend."

  @type type :: :git
  @type ref_kind :: :branch | :tag | :revision | :unknown
  @type dirty_policy :: :error | :reset | :ignore

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          type: type(),
          uri: String.t(),
          ref: String.t(),
          ref_kind: ref_kind(),
          revision: String.t() | nil,
          checkout: String.t(),
          path: String.t(),
          dirty: dirty_policy(),
          depends_on: [term()],
          meta: map()
        }

  defstruct name: nil,
            type: :git,
            uri: nil,
            ref: "HEAD",
            ref_kind: :unknown,
            revision: nil,
            checkout: nil,
            path: ".",
            dirty: :error,
            depends_on: [],
            meta: %{}

  @spec new(atom() | String.t(), keyword()) :: t()
  def new(name, opts) do
    %__MODULE__{
      name: name,
      type: :git,
      uri: uri!(opts),
      ref: opts |> Keyword.get(:ref, "HEAD") |> to_string(),
      checkout: Keyword.fetch!(opts, :checkout),
      path: opts |> Keyword.get(:path, ".") |> to_string(),
      dirty: Keyword.get(opts, :dirty, :error),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def id(%__MODULE__{name: name}), do: {:source, name}

  def app_path(%__MODULE__{checkout: checkout, path: "."}), do: checkout
  def app_path(%__MODULE__{checkout: checkout, path: path}), do: Path.join(checkout, path)

  def identity(%__MODULE__{} = source) do
    %{
      "type" => Atom.to_string(source.type),
      "uri" => source.uri,
      "ref" => source.ref,
      "ref_kind" => Atom.to_string(source.ref_kind),
      "revision" => source.revision,
      "tree" => Map.get(source.meta, :tree),
      "checkout" => source.checkout,
      "path" => source.path
    }
  end

  defp uri!(opts) do
    cond do
      uri = Keyword.get(opts, :git) -> uri
      uri = Keyword.get(opts, :url) -> uri
      github = Keyword.get(opts, :github) -> "https://github.com/#{github}.git"
      true -> raise ArgumentError, "source expects :git, :url, or :github"
    end
  end
end
