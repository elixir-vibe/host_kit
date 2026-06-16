defmodule HostKit.Conventions do
  @moduledoc "Project-level naming and path conventions."

  alias HostKit.Naming

  @type t :: %__MODULE__{
          roots: %{optional(atom()) => String.t()},
          prefixes: %{optional(atom()) => String.t()}
        }

  @default_state_root "/var/lib/hostkit"
  @default_workspaces_root "/var/lib/hostkit/workspaces"
  @default_roots %{bin: "/usr/local/bin", sbin: "/usr/local/sbin"}

  defstruct roots: %{}, prefixes: %{}

  @spec new(keyword() | map()) :: t()
  def new(attrs \\ []) do
    %__MODULE__{
      roots: attrs |> get(:roots, %{}) |> Map.new(),
      prefixes: attrs |> get(:prefixes, %{}) |> Map.new()
    }
  end

  @spec put_root(t(), atom(), String.t()) :: t()
  def put_root(%__MODULE__{} = conventions, name, path) when is_atom(name) do
    %{conventions | roots: Map.put(conventions.roots, name, path)}
  end

  @spec put_prefix(t(), atom(), String.t()) :: t()
  def put_prefix(%__MODULE__{} = conventions, name, prefix) when is_atom(name) do
    %{conventions | prefixes: Map.put(conventions.prefixes, name, prefix)}
  end

  @spec root!(t() | map(), atom()) :: String.t()
  def root!(conventions, name) do
    conventions = normalize(conventions)

    case Map.fetch!(conventions, :roots) do
      %{^name => root} -> root
      _roots -> Map.fetch!(@default_roots, name)
    end
  end

  @doc "Returns the HostKit state root, defaulting to /var/lib/hostkit."
  @spec state_root(t() | map()) :: String.t()
  def state_root(conventions), do: root(conventions, :hostkit_state, @default_state_root)

  @doc "Returns the root used for minimal HostKit run records."
  @spec runs_root(t() | map()) :: String.t()
  def runs_root(conventions),
    do: root(conventions, :hostkit_runs, Path.join(state_root(conventions), "runs"))

  @doc "Returns the root used for rollback backup payloads."
  @spec backups_root(t() | map()) :: String.t()
  def backups_root(conventions),
    do: root(conventions, :hostkit_backups, Path.join(state_root(conventions), "backups"))

  @doc "Returns the root used for workspace service directories."
  @spec workspaces_root(t() | map()) :: String.t()
  def workspaces_root(conventions) do
    conventions = normalize(conventions)

    root(
      conventions,
      :workspaces,
      root(conventions, :data, @default_workspaces_root)
    )
  end

  @spec root(t() | map(), atom(), String.t()) :: String.t()
  def root(conventions, name, default) do
    conventions
    |> normalize()
    |> Map.fetch!(:roots)
    |> Map.get(name, Map.get(@default_roots, name, default))
  end

  @spec prefixed(t() | map(), atom(), term()) :: String.t()
  def prefixed(conventions, name, value) do
    prefix = conventions |> normalize() |> Map.fetch!(:prefixes) |> Map.get(name, "")
    Naming.prefixed(prefix, value)
  end

  defp normalize(%__MODULE__{} = conventions), do: Map.from_struct(conventions)
  defp normalize(conventions) when is_map(conventions), do: conventions

  defp get(attrs, key, default) when is_list(attrs), do: Keyword.get(attrs, key, default)
  defp get(attrs, key, default) when is_map(attrs), do: Map.get(attrs, key, default)
end
