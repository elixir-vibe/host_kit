defmodule HostKit.DSLCore.Scope do
  @moduledoc "A single active DSL scope with state and source location metadata."

  @type location :: %{
          file: String.t() | nil,
          line: pos_integer() | nil,
          column: pos_integer() | nil
        }

  @type t :: %__MODULE__{
          name: atom(),
          state: term(),
          location: location() | nil
        }

  defstruct [:name, :state, :location]

  @doc "Build a scope value."
  @spec new(atom(), term(), Macro.Env.t() | location() | nil) :: t()
  def new(name, state, location \\ nil) when is_atom(name) do
    %__MODULE__{name: name, state: state, location: normalize_location(location)}
  end

  defp normalize_location(%Macro.Env{} = env) do
    %{file: env.file, line: env.line, column: nil}
  end

  defp normalize_location(%{file: _file, line: _line} = location), do: location
  defp normalize_location(nil), do: nil
end
