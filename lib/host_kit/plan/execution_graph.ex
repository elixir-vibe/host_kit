defmodule HostKit.Plan.ExecutionGraph do
  @moduledoc "Builds an inspectable dependency graph for HostKit plan changes."

  alias HostKit.Plan
  alias HostKit.Plan.ExecutionGraph.{Build, Edge, Format, JSON, Node}

  @type t :: %__MODULE__{
          nodes: [Node.t()],
          edges: [Edge.t()],
          layers: [[term()]],
          cycles: [[term()]]
        }

  defstruct nodes: [], edges: [], layers: [], cycles: []

  @doc "Builds an execution dependency graph from active plan changes."
  @spec build(Plan.t(), keyword()) :: t()
  defdelegate build(plan, opts \\ []), to: Build

  @doc "Returns true when the graph has no cycle diagnostics."
  @spec acyclic?(t()) :: boolean()
  def acyclic?(%__MODULE__{cycles: cycles}), do: cycles == []

  @doc "Returns a JSON-safe map for machine-readable graph output."
  @spec to_json(t()) :: map()
  defdelegate to_json(graph), to: JSON

  @doc "Formats a concise text rendering of the execution graph."
  @spec format(t()) :: String.t()
  defdelegate format(graph), to: Format
end
