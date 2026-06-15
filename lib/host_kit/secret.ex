defmodule HostKit.Secret do
  @moduledoc "References to secrets resolved at HostKit control-plane boundaries."

  @type source :: {:env, String.t()}
  @type t :: %__MODULE__{source: source()}

  defstruct source: nil

  @spec env(String.t()) :: t()
  def env(name) when is_binary(name), do: %__MODULE__{source: {:env, name}}

  @spec secret?(term()) :: boolean()
  def secret?(%__MODULE__{}), do: true
  def secret?(:redacted), do: true
  def secret?(%{} = map), do: Enum.any?(map, fn {_key, value} -> secret?(value) end)

  def secret?(values) when is_list(values) do
    if Keyword.keyword?(values),
      do: Enum.any?(values, fn {_key, value} -> secret?(value) end),
      else: Enum.any?(values, &secret?/1)
  end

  def secret?(_value), do: false

  @spec resolve!(term()) :: term()
  def resolve!(%__MODULE__{source: {:env, name}}), do: System.fetch_env!(name)
  def resolve!(value), do: value
end
