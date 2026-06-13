defmodule HostKit.Secret do
  @moduledoc "References to secrets resolved at HostKit control-plane boundaries."

  @type source :: {:env, String.t()}
  @type t :: %__MODULE__{source: source()}

  defstruct source: nil

  @spec env(String.t()) :: t()
  def env(name) when is_binary(name), do: %__MODULE__{source: {:env, name}}

  @spec resolve!(term()) :: term()
  def resolve!(%__MODULE__{source: {:env, name}}), do: System.fetch_env!(name)
  def resolve!(value), do: value
end
