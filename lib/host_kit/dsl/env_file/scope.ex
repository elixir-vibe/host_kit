defmodule HostKit.DSL.EnvFile.Scope do
  @moduledoc false

  use HostKit.DSLCore

  scope(:env_file)

  def start(path, opts) do
    env_file =
      HostKit.Resources.EnvFile.new(path, Keyword.put_new(opts, :mode, :secret_group_file))

    push_env_file(env_file)
  end

  def finish do
    pop_env_file()
  end

  def active?, do: env_file_active?()

  def put_set(key, value) do
    update_env_file(
      &%{&1 | entries: &1.entries ++ [{:set, normalize_key(key), to_string(value)}]}
    )
  end

  def put_secret(key, opts) do
    update_env_file(
      &%{
        &1
        | entries: &1.entries ++ [{:secret, normalize_key(key), HostKit.Secret.from_opts!(opts)}]
      }
    )
  end

  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> String.upcase()
  defp normalize_key(key), do: to_string(key)
end
