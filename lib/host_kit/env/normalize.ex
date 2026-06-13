defmodule HostKit.Env.Normalize do
  @moduledoc false

  def string_map(env) when is_map(env) do
    Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  def string_map(env) when is_list(env) do
    env |> Map.new() |> string_map()
  end
end
