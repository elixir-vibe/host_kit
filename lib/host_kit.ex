defmodule HostKit do
  @moduledoc """
  Elixir-native host infrastructure declarations, planning, and runtime control.

  HostKit keeps systemd and transient unit execution as core primitives while
  integrations such as Caddy are provided by plugins. DSL files compile to plain
  structs that can be inspected and consumed through the runtime API.
  """

  alias HostKit.{Loader, Plan, Project}

  @doc "Loads a HostKit project from an `.exs` file."
  @spec load(Path.t(), keyword()) :: {:ok, Project.t()} | {:error, term()}
  def load(path, opts \\ []), do: Loader.load(path, opts)

  @doc "Loads a HostKit project from an `.exs` file or raises."
  @spec load!(Path.t(), keyword()) :: Project.t()
  def load!(path, opts \\ []) do
    case load(path, opts) do
      {:ok, project} ->
        project

      {:error, reason} ->
        raise ArgumentError, "could not load HostKit project: #{inspect(reason)}"
    end
  end

  @doc """
  Builds an initial plan from project resources.

  This first implementation is intentionally structural: it preserves resources
  and dependency ordering without touching a host.
  """
  @spec plan(Project.t(), keyword()) :: {:ok, Plan.t()}
  def plan(%Project{} = project, opts \\ []), do: Plan.build(project, opts)
end
