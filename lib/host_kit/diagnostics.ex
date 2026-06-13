defmodule HostKit.Diagnostics do
  @moduledoc "Collection of HostKit diagnostics."

  alias HostKit.Diagnostic

  @type t :: %__MODULE__{errors: [Diagnostic.t()], warnings: [Diagnostic.t()]}

  defstruct errors: [], warnings: []

  @spec new([Diagnostic.t()]) :: t()
  def new(diagnostics \\ []) do
    Enum.reduce(diagnostics, %__MODULE__{}, &add(&2, &1))
  end

  @spec add(t(), Diagnostic.t()) :: t()
  def add(%__MODULE__{} = diagnostics, %Diagnostic{severity: :warning} = diagnostic) do
    %{diagnostics | warnings: diagnostics.warnings ++ [diagnostic]}
  end

  def add(%__MODULE__{} = diagnostics, %Diagnostic{} = diagnostic) do
    %{diagnostics | errors: diagnostics.errors ++ [diagnostic]}
  end

  @spec ok?(t()) :: boolean()
  def ok?(%__MODULE__{errors: []}), do: true
  def ok?(%__MODULE__{}), do: false

  @spec all(t()) :: [Diagnostic.t()]
  def all(%__MODULE__{} = diagnostics), do: diagnostics.errors ++ diagnostics.warnings
end
