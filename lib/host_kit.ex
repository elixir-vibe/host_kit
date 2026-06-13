defmodule HostKit do
  import Kernel, except: [apply: 2]

  @moduledoc """
  Elixir-native host infrastructure declarations, planning, and runtime control.

  HostKit keeps systemd and transient unit execution as core primitives while
  integrations such as Caddy are provided by providers. DSL files compile to plain
  structs that can be inspected and consumed through the runtime API.
  """

  alias HostKit.{Apply, Loader, Plan, Project, Target}

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
  @spec plan(Project.t(), keyword()) ::
          {:ok, Plan.t()} | {:error, HostKit.Diagnostics.t() | term()}
  def plan(%Project{} = project, opts \\ []), do: Plan.build(project, expand_target_opts(opts))

  @doc "Applies supported changes from a HostKit plan."
  @spec apply(Plan.t(), keyword()) :: {:ok, [Apply.result()]} | {:error, term()}
  def apply(%Plan{} = plan, opts \\ []), do: Apply.run(plan, expand_target_opts(opts))

  @doc "Applies supported changes from a HostKit plan or raises."
  @spec apply!(Plan.t(), keyword()) :: [Apply.result()]
  def apply!(%Plan{} = plan, opts \\ []) do
    case apply(plan, opts) do
      {:ok, results} ->
        results

      {:error, reason} ->
        raise ArgumentError, "could not apply HostKit plan: #{inspect(reason)}"
    end
  end

  @doc "Formats a HostKit plan for human-readable output."
  @spec format_plan(Plan.t()) :: String.t()
  def format_plan(%Plan{} = plan), do: Plan.Format.format(plan)

  defp expand_target_opts(opts) do
    case Keyword.pop(opts, :target) do
      {%Target{} = target, opts} -> Target.opts(target, opts)
      {nil, opts} -> opts
    end
  end
end
